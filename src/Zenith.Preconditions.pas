{
    Zenith Framework - RFC 7232 / RFC 9110 Conditional Requests & Preconditions

    Implements full normative evaluation of HTTP conditional request headers:
    - If-Match (strong ETag comparison, wildcard '*', OCC 412 Precondition Failed)
    - If-Unmodified-Since (RFC 7231 HTTP-date, 1-second granularity, OCC 412)
    - If-None-Match (weak ETag comparison, wildcard '*', 304 Not Modified on
      GET/HEAD with zero body allocation, 412 on state-changing methods)
    - If-Modified-Since (RFC 7231 HTTP-date, GET/HEAD only, 304 Not Modified)
    - Strict RFC 7232 Section 6 evaluation precedence
    - RFC 9457 Problem Details (application/problem+json) on HTTP 412 responses
    - Locale-independent RFC 7231 Section 7.1.1.1 HTTP-date formatting & parsing
      (IMF-fixdate, obsolete RFC 850, and ANSI C asctime)
}

unit Zenith.Preconditions;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, HTTPDefs, httpprotocol,
  Zenith.Consts, DeltaModel, DeltaModel.ETag;

type
  { Outcome of evaluating RFC 7232 conditional request headers }
  TPreconditionResult = (
    prProceed,             { All preconditions satisfied; execute handler normally }
    prNotModified,         { HTTP 304 Not Modified (GET/HEAD cache hit; empty body) }
    prPreconditionFailed   { HTTP 412 Precondition Failed (OCC / state mismatch) }
  );

  { Detailed result record returned by Evaluate }
  TPreconditionEvaluation = record
    Outcome: TPreconditionResult;
    StatusCode: Integer;
    FailedHeader: string;
    Detail: string;
  end;

  { Conditional request evaluator and response helper (RFC 7232 / RFC 9110) }
  TZenithPreconditions = class
  public
    { Reads a request header checking both standard HTTPDefs slot and CustomHeaders }
    class function GetHeaderValue(ARequest: TRequest; AStandardHeader: THeader;
      const AHeaderName: string): string;

    { Evaluates RFC 7232 Section 6 precedence directly from header values }
    class function Evaluate(
      const AMethod: string;
      const AIfMatch, AIfUnmodifiedSince, AIfNoneMatch, AIfModifiedSince: string;
      const ACurrentETag: string;
      ALastModifiedUTC: TDateTime = 0;
      AResourceExists: Boolean = True
    ): TPreconditionEvaluation; overload;

    { Evaluates RFC 7232 Section 6 precedence directly from a TRequest instance }
    class function Evaluate(
      ARequest: TRequest;
      const ACurrentETag: string;
      ALastModifiedUTC: TDateTime = 0;
      AResourceExists: Boolean = True
    ): TPreconditionEvaluation; overload;

    { Sets ETag and optional Last-Modified headers on AResponse }
    class procedure SetValidators(AResponse: TResponse; const AETag: string;
      ALastModifiedUTC: TDateTime = 0);

    { Writes HTTP 304 Not Modified with empty body (zero payload allocation) }
    class procedure WriteNotModified(AResponse: TResponse; const AETag: string;
      ALastModifiedUTC: TDateTime = 0);

    { Writes HTTP 412 Precondition Failed with RFC 9457 Problem Details JSON }
    class procedure WritePreconditionFailed(AResponse: TResponse;
      const ADetail: string; const ACurrentETag: string = '');

    { Evaluates preconditions and automatically writes 304 or 412 to AResponse.
      Returns True if the route handler should continue processing;
      Returns False if the response has already been finalized (304 or 412). }
    class function Check(
      ARequest: TRequest;
      AResponse: TResponse;
      const ACurrentETag: string;
      ALastModifiedUTC: TDateTime = 0;
      AResourceExists: Boolean = True
    ): Boolean;

    { Convenience overload computing ETag directly from a TDeltaModel instance }
    class function CheckModel(
      ARequest: TRequest;
      AResponse: TResponse;
      AModel: TDeltaModel;
      AWeakETag: Boolean = False;
      ALastModifiedUTC: TDateTime = 0;
      AAlgorithm: TETagHashAlgorithm = ehaSHA256
    ): Boolean;
  end;

{ Formats a UTC TDateTime as an RFC 7231 IMF-fixdate (e.g. "Sun, 06 Nov 1994 08:49:37 GMT") }
function FormatHTTPDate(AUTCDateTime: TDateTime): string;

{ Parses an RFC 7231 HTTP-date (IMF-fixdate, RFC 850, or ANSI C asctime) into UTC TDateTime }
function TryParseHTTPDate(const AValue: string; out AUTCDateTime: TDateTime): Boolean;

{ Truncates a UTC TDateTime to whole seconds (RFC 7232 1-second timestamp resolution) }
function TruncateToHTTPSeconds(AUTCDateTime: TDateTime): Int64;

implementation

const
  HTTP_DAYS_SHORT: array[1..7] of string = (
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
  );
  HTTP_MONTHS_SHORT: array[1..12] of string = (
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  );

function IsReadOnlyMethod(const AMethod: string): Boolean; inline;
begin
  Result := SameText(AMethod, 'GET') or SameText(AMethod, 'HEAD');
end;

function ParseMonthShort(const AMonth: string; out AMonthNum: Word): Boolean;
var
  I: Word;
begin
  for I := 1 to 12 do
  begin
    if SameText(AMonth, HTTP_MONTHS_SHORT[I]) then
    begin
      AMonthNum := I;
      Exit(True);
    end;
  end;
  AMonthNum := 0;
  Result := False;
end;

function ParseTimeHMS(const ATimeStr: string; out AHour, AMin, ASec: Word): Boolean;
var
  H, M, S: Integer;
begin
  Result := False;
  if (Length(ATimeStr) <> 8) or (ATimeStr[3] <> ':') or (ATimeStr[6] <> ':') then
    Exit;
  if (not TryStrToInt(Copy(ATimeStr, 1, 2), H)) or
     (not TryStrToInt(Copy(ATimeStr, 4, 2), M)) or
     (not TryStrToInt(Copy(ATimeStr, 7, 2), S)) then
    Exit;
  if (H < 0) or (H > 23) or (M < 0) or (M > 59) or (S < 0) or (S > 60) then
    Exit;
  if S = 60 then S := 59; { Leap second clamp }
  AHour := Word(H);
  AMin := Word(M);
  ASec := Word(S);
  Result := True;
end;

function JsonEscapeString(const AStr: string): string;
var
  I: SizeInt;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(AStr) do
  begin
    C := AStr[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8:  Result := Result + '\b';
      #9:  Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      Result := Result + C;
    end;
  end;
end;

function FormatHTTPDate(AUTCDateTime: TDateTime): string;
var
  Year, Month, Day, Hour, Min, Sec, MSec: Word;
  DOW: Word;
begin
  DecodeDateTime(AUTCDateTime, Year, Month, Day, Hour, Min, Sec, MSec);
  DOW := DayOfWeek(AUTCDateTime); { 1 = Sunday .. 7 = Saturday }
  Result := Format('%s, %.2d %s %.4d %.2d:%.2d:%.2d GMT', [
    HTTP_DAYS_SHORT[DOW],
    Day,
    HTTP_MONTHS_SHORT[Month],
    Year,
    Hour,
    Min,
    Sec
  ]);
end;

function TryParseHTTPDate(const AValue: string; out AUTCDateTime: TDateTime): Boolean;
var
  S: string;
  CommaPos, SpacePos: SizeInt;
  Rest, DayStr, MonStr, YearStr, TimeStr, TzStr: string;
  DayNum, MonthNum, YearNum, HourNum, MinNum, SecNum: Word;
  DayInt, YearInt: Integer;
  Parts: TStringArray;
  CleanParts: array of string;
  I, CleanCount: Integer;
  Dash1, Dash2: SizeInt;
begin
  AUTCDateTime := 0;
  Result := False;
  S := Trim(AValue);
  if Length(S) < 20 then
    Exit;

  CommaPos := Pos(',', S);
  if CommaPos > 0 then
  begin
    { Format 1 (IMF-fixdate): "Sun, 06 Nov 1994 08:49:37 GMT"
      Format 2 (RFC 850):     "Sunday, 06-Nov-94 08:49:37 GMT" }
    Rest := Trim(Copy(S, CommaPos + 1, MaxInt));
    Parts := Rest.Split([' ']);
    CleanCount := 0;
    SetLength(CleanParts, Length(Parts));
    for I := 0 to High(Parts) do
      if Parts[I] <> '' then
      begin
        CleanParts[CleanCount] := Parts[I];
        Inc(CleanCount);
      end;

    if CleanCount = 5 then
    begin
      { IMF-fixdate: DD Mon YYYY HH:MM:SS GMT }
      DayStr := CleanParts[0];
      MonStr := CleanParts[1];
      YearStr := CleanParts[2];
      TimeStr := CleanParts[3];
      TzStr := CleanParts[4];

      if not SameText(TzStr, 'GMT') then Exit;
      if (not TryStrToInt(DayStr, DayInt)) or (DayInt < 1) or (DayInt > 31) then Exit;
      if not ParseMonthShort(MonStr, MonthNum) then Exit;
      if (not TryStrToInt(YearStr, YearInt)) or (YearInt < 1900) or (YearInt > 9999) then Exit;
      if not ParseTimeHMS(TimeStr, HourNum, MinNum, SecNum) then Exit;

      DayNum := Word(DayInt);
      YearNum := Word(YearInt);
      if not TryEncodeDateTime(YearNum, MonthNum, DayNum, HourNum, MinNum, SecNum, 0, AUTCDateTime) then
        Exit;
      Exit(True);
    end
    else if CleanCount = 3 then
    begin
      { RFC 850: DD-Mon-YY HH:MM:SS GMT }
      Dash1 := Pos('-', CleanParts[0]);
      if Dash1 <= 1 then Exit;
      Dash2 := Pos('-', Copy(CleanParts[0], Dash1 + 1, MaxInt));
      if Dash2 <= 1 then Exit;
      Dash2 := Dash1 + Dash2;

      DayStr := Copy(CleanParts[0], 1, Dash1 - 1);
      MonStr := Copy(CleanParts[0], Dash1 + 1, Dash2 - Dash1 - 1);
      YearStr := Copy(CleanParts[0], Dash2 + 1, MaxInt);
      TimeStr := CleanParts[1];
      TzStr := CleanParts[2];

      if not SameText(TzStr, 'GMT') then Exit;
      if (not TryStrToInt(DayStr, DayInt)) or (DayInt < 1) or (DayInt > 31) then Exit;
      if not ParseMonthShort(MonStr, MonthNum) then Exit;
      if (not TryStrToInt(YearStr, YearInt)) or (YearInt < 0) or (YearInt > 99) then Exit;
      if YearInt >= 70 then
        YearInt := 1900 + YearInt
      else
        YearInt := 2000 + YearInt;
      if not ParseTimeHMS(TimeStr, HourNum, MinNum, SecNum) then Exit;

      DayNum := Word(DayInt);
      YearNum := Word(YearInt);
      if not TryEncodeDateTime(YearNum, MonthNum, DayNum, HourNum, MinNum, SecNum, 0, AUTCDateTime) then
        Exit;
      Exit(True);
    end;
  end
  else
  begin
    { Format 3 (ANSI C asctime): "Sun Nov  6 08:49:37 1994" }
    SpacePos := Pos(' ', S);
    if SpacePos <= 1 then Exit;
    Parts := S.Split([' ']);
    CleanCount := 0;
    SetLength(CleanParts, Length(Parts));
    for I := 0 to High(Parts) do
      if Parts[I] <> '' then
      begin
        CleanParts[CleanCount] := Parts[I];
        Inc(CleanCount);
      end;

    if CleanCount = 5 then
    begin
      MonStr := CleanParts[1];
      DayStr := CleanParts[2];
      TimeStr := CleanParts[3];
      YearStr := CleanParts[4];

      if not ParseMonthShort(MonStr, MonthNum) then Exit;
      if (not TryStrToInt(DayStr, DayInt)) or (DayInt < 1) or (DayInt > 31) then Exit;
      if (not TryStrToInt(YearStr, YearInt)) or (YearInt < 1900) or (YearInt > 9999) then Exit;
      if not ParseTimeHMS(TimeStr, HourNum, MinNum, SecNum) then Exit;

      DayNum := Word(DayInt);
      YearNum := Word(YearInt);
      if not TryEncodeDateTime(YearNum, MonthNum, DayNum, HourNum, MinNum, SecNum, 0, AUTCDateTime) then
        Exit;
      Exit(True);
    end;
  end;
end;

function TruncateToHTTPSeconds(AUTCDateTime: TDateTime): Int64;
begin
  Result := DateTimeToUnix(AUTCDateTime, True);
end;

{ TZenithPreconditions }

class function TZenithPreconditions.GetHeaderValue(ARequest: TRequest;
  AStandardHeader: THeader; const AHeaderName: string): string;
begin
  if ARequest = nil then
    Exit('');

  Result := Trim(ARequest.GetHeader(AStandardHeader));
  if Result = '' then
    Result := Trim(ARequest.GetCustomHeader(AHeaderName));
  if Result = '' then
    Result := Trim(ARequest.CustomHeaders.Values[AHeaderName]);
end;

class function TZenithPreconditions.Evaluate(
  const AMethod: string;
  const AIfMatch, AIfUnmodifiedSince, AIfNoneMatch, AIfModifiedSince: string;
  const ACurrentETag: string;
  ALastModifiedUTC: TDateTime = 0;
  AResourceExists: Boolean = True
): TPreconditionEvaluation;
var
  IfMatchVal, IfUnmodVal, IfNoneMatchVal, IfModVal: string;
  HeaderDate: TDateTime;
  LastModSec, HeaderSec: Int64;
begin
  Result.Outcome := prProceed;
  Result.StatusCode := 0;
  Result.FailedHeader := '';
  Result.Detail := '';

  IfMatchVal := Trim(AIfMatch);
  IfUnmodVal := Trim(AIfUnmodifiedSince);
  IfNoneMatchVal := Trim(AIfNoneMatch);
  IfModVal := Trim(AIfModifiedSince);

  { =========================================================================
    RFC 7232 Section 6 — Step 1: If-Match
    Uses Strong Comparison. If present, If-Unmodified-Since MUST be ignored.
    ========================================================================= }
  if IfMatchVal <> '' then
  begin
    if not MatchesETagList(ACurrentETag, IfMatchVal, True, AResourceExists) then
    begin
      Result.Outcome := prPreconditionFailed;
      Result.StatusCode := StatusPreconditionFailed;
      Result.FailedHeader := 'If-Match';
      Result.Detail := 'Resource entity tag does not match the If-Match precondition.';
      Exit;
    end;
    { Step 1 true -> skip Step 2 and continue to Step 3 }
  end
  { =========================================================================
    RFC 7232 Section 6 — Step 2: If-Unmodified-Since
    Evaluated ONLY when If-Match is absent. Invalid HTTP-dates MUST be ignored.
    ========================================================================= }
  else if IfUnmodVal <> '' then
  begin
    if (ALastModifiedUTC > 0) and TryParseHTTPDate(IfUnmodVal, HeaderDate) then
    begin
      LastModSec := TruncateToHTTPSeconds(ALastModifiedUTC);
      HeaderSec := TruncateToHTTPSeconds(HeaderDate);
      if LastModSec > HeaderSec then
      begin
        Result.Outcome := prPreconditionFailed;
        Result.StatusCode := StatusPreconditionFailed;
        Result.FailedHeader := 'If-Unmodified-Since';
        Result.Detail := 'Resource has been modified after the If-Unmodified-Since timestamp.';
        Exit;
      end;
    end;
  end;

  { =========================================================================
    RFC 7232 Section 6 — Step 3: If-None-Match
    Uses Weak Comparison. If present, If-Modified-Since MUST be ignored.
    On match: GET/HEAD -> 304 Not Modified; other methods -> 412 Precondition Failed.
    ========================================================================= }
  if IfNoneMatchVal <> '' then
  begin
    if MatchesETagList(ACurrentETag, IfNoneMatchVal, False, AResourceExists) then
    begin
      if IsReadOnlyMethod(AMethod) then
      begin
        Result.Outcome := prNotModified;
        Result.StatusCode := StatusNotModified;
        Result.FailedHeader := 'If-None-Match';
        Result.Detail := '';
      end
      else
      begin
        Result.Outcome := prPreconditionFailed;
        Result.StatusCode := StatusPreconditionFailed;
        Result.FailedHeader := 'If-None-Match';
        Result.Detail := 'Resource matches an entity tag prohibited by the If-None-Match precondition.';
      end;
      Exit;
    end;
    { Step 3 true (no match) -> skip Step 4 and proceed }
    Exit;
  end;

  { =========================================================================
    RFC 7232 Section 6 — Step 4: If-Modified-Since
    Evaluated ONLY for GET/HEAD when If-None-Match is absent.
    Invalid HTTP-dates MUST be ignored.
    ========================================================================= }
  if IsReadOnlyMethod(AMethod) and (IfModVal <> '') then
  begin
    if (ALastModifiedUTC > 0) and TryParseHTTPDate(IfModVal, HeaderDate) then
    begin
      LastModSec := TruncateToHTTPSeconds(ALastModifiedUTC);
      HeaderSec := TruncateToHTTPSeconds(HeaderDate);
      if LastModSec <= HeaderSec then
      begin
        Result.Outcome := prNotModified;
        Result.StatusCode := StatusNotModified;
        Result.FailedHeader := 'If-Modified-Since';
        Result.Detail := '';
        Exit;
      end;
    end;
  end;
end;

class function TZenithPreconditions.Evaluate(
  ARequest: TRequest;
  const ACurrentETag: string;
  ALastModifiedUTC: TDateTime = 0;
  AResourceExists: Boolean = True
): TPreconditionEvaluation;
begin
  if ARequest = nil then
  begin
    Result.Outcome := prProceed;
    Result.StatusCode := 0;
    Result.FailedHeader := '';
    Result.Detail := '';
    Exit;
  end;

  Result := Evaluate(
    ARequest.Method,
    GetHeaderValue(ARequest, hhIfMatch, 'If-Match'),
    GetHeaderValue(ARequest, hhIfUnmodifiedSince, 'If-Unmodified-Since'),
    GetHeaderValue(ARequest, hhIfNoneMatch, 'If-None-Match'),
    GetHeaderValue(ARequest, hhIfModifiedSince, 'If-Modified-Since'),
    ACurrentETag,
    ALastModifiedUTC,
    AResourceExists
  );
end;

class procedure TZenithPreconditions.SetValidators(AResponse: TResponse;
  const AETag: string; ALastModifiedUTC: TDateTime = 0);
begin
  if AResponse = nil then Exit;
  if AETag <> '' then
    AResponse.SetHeader(hhETag, AETag);
  if ALastModifiedUTC > 0 then
    AResponse.SetHeader(hhLastModified, FormatHTTPDate(ALastModifiedUTC));
end;

class procedure TZenithPreconditions.WriteNotModified(AResponse: TResponse;
  const AETag: string; ALastModifiedUTC: TDateTime = 0);
begin
  if AResponse = nil then Exit;
  AResponse.Code := StatusNotModified;
  SetValidators(AResponse, AETag, ALastModifiedUTC);
  { Zero payload allocation: ensure body is strictly empty per RFC 7232 Section 4.1 }
  if Assigned(AResponse.ContentStream) then
    AResponse.ContentStream := nil;
  AResponse.Content := '';
  AResponse.ContentLength := 0;
end;

class procedure TZenithPreconditions.WritePreconditionFailed(AResponse: TResponse;
  const ADetail: string; const ACurrentETag: string = '');
begin
  if AResponse = nil then Exit;
  AResponse.Code := StatusPreconditionFailed;
  AResponse.ContentType := ApplicationProblemJson;
  if ACurrentETag <> '' then
    AResponse.SetHeader(hhETag, ACurrentETag);
  AResponse.Content :=
    '{"type":"https://tools.ietf.org/html/rfc7232#section-4.2",' +
    '"title":"Precondition Failed",' +
    '"status":412,' +
    '"detail":"' + JsonEscapeString(ADetail) + '"}';
end;

class function TZenithPreconditions.Check(
  ARequest: TRequest;
  AResponse: TResponse;
  const ACurrentETag: string;
  ALastModifiedUTC: TDateTime = 0;
  AResourceExists: Boolean = True
): Boolean;
var
  Eval: TPreconditionEvaluation;
begin
  Eval := Evaluate(ARequest, ACurrentETag, ALastModifiedUTC, AResourceExists);
  case Eval.Outcome of
    prNotModified:
      begin
        WriteNotModified(AResponse, ACurrentETag, ALastModifiedUTC);
        Result := False;
      end;
    prPreconditionFailed:
      begin
        WritePreconditionFailed(AResponse, Eval.Detail, ACurrentETag);
        Result := False;
      end;
  else
    begin
      if AResourceExists then
        SetValidators(AResponse, ACurrentETag, ALastModifiedUTC);
      Result := True;
    end;
  end;
end;

class function TZenithPreconditions.CheckModel(
  ARequest: TRequest;
  AResponse: TResponse;
  AModel: TDeltaModel;
  AWeakETag: Boolean = False;
  ALastModifiedUTC: TDateTime = 0;
  AAlgorithm: TETagHashAlgorithm = ehaSHA256
): Boolean;
var
  Tag: string;
begin
  if AModel = nil then
    Result := Check(ARequest, AResponse, '', ALastModifiedUTC, False)
  else
  begin
    Tag := CalculateETag(AModel, AWeakETag, AAlgorithm);
    Result := Check(ARequest, AResponse, Tag, ALastModifiedUTC, True);
  end;
end;

end.
