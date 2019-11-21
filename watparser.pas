unit watparser;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, wasmtext, wasmmodule, watscanner, wasmbincode, wasmbin;

type
  TParseResult = record
    error  : string;
    line   : integer;
    pos    : integer;
    offset : integer;
  end;

const
  TokenStr : array[TWatToken] of string = (
     'uknown', 'error',
     'index',
     'string', 'number', '(', ')',
     'linksymbol',

     'instruction',
     'func',
     'param', 'result',
     'module', 'mut', 'funcref',
     'i32', 'i64',
     'f32', 'f64',
     'type',
     'import', 'global', 'table', 'memory', 'local', 'export',
     'elem', 'data', 'offset'
     );

//function ConsumeToken(sc: TWatScanner; tk: TWatToken): Boolean;
function ParseModule(sc: TWatScanner; dst: TWasmModule; var errMsg: string): Boolean; overload;
function ParseModule(sc: TWatScanner; dst: TWasmModule; out err: TParseResult): Boolean; overload;

type
  // used to stop the recursive parsing

  { EParserError }

  EParserError = class(Exception)
    offset : integer;
    constructor Create(const amsg: string; aofs: integer);
  end;

implementation

const
  WAT_DEFTYPES='iN or fN';

procedure ParseError(sc: TWatScanner; const errMsg: string);
begin
  raise EParserError.Create(errMsg, sc.ofs);
end;

procedure ErrorExpectButFound(sc: TWatScanner; const expected: string; const butfound: string  =''); overload;
var
  r : string;
begin
  if butfound = '' then r := sc.resText
  else r := butfound;
  ParseError(sc, 'expected "'+expected+'", but "'+r+'" found');
end;

procedure ErrorUnexpectedEof(sc: TWatScanner);
begin
  ParseError(sc, 'unexpected end of file');
end;

procedure ConsumeAnyOpenToken(sc: TWatScanner; out tk: TWatToken;
  out hadOpenBrace: Boolean); overload;
begin
  hadOpenBrace := sc.token = weOpenBrace;
  if hadOpenBrace then sc.Next;
  tk:=sc.token;
end;

procedure ConsumeAnyOpenToken(sc: TWatScanner); overload;
var
  tk: TWatToken;
  op: Boolean;
begin
  ConsumeAnyOpenToken(sc, tk, op);
end;

procedure ConsumeAnyOpenToken(sc: TWatScanner; out tk: TWatToken); overload;
var
  op: Boolean;
begin
  ConsumeAnyOpenToken(sc, tk, op);
end;


function ConsumeOpenToken(sc: TWatScanner; tk: TWatToken): Boolean;
begin
  sc.Next;
  Result := (sc.token=weOpenBrace) or (sc.Token=tk);
  if Result and (sc.token=weOpenBrace) then begin
    sc.Next;
    Result := (sc.Token=tk);
  end;
end;

function ConsumeToken(sc: TWatScanner; tk: TWatToken): Boolean;
begin
  Result:=sc.token =tk;
  if not Result then
    ErrorExpectButFound(sc,TokenStr[tk])
  else
    sc.Next;
end;

function ParseNumOfId(sc: TWatScanner; out num: integer; out id: string): Boolean;
begin
  num:=-1;
  id:='';
  Result := sc.Next;
  if not Result then begin
    ErrorUnexpectedEof(sc);
    Exit;
  end;

  case sc.token of
    weNumber: num:=sc.resInt32;
    weIdent: id:=sc.resText;
  else
    ErrorExpectButFound(sc, 'index', TokenStr[sc.token]);
    Result := false;
  end;
  Result := true;
  if Result then sc.Next;
end;

function TokenTypeToValType(t: TWatToken; out tp: byte): Boolean;
begin
  Result:=true;
  case t of
    wei32: tp:=valtype_i32;
    wei64: tp:=valtype_i64;
    wef32: tp:=valtype_f32;
    wef64: tp:=valtype_f64;
  else
    tp:=0;
    Result:=false;
  end;
end;

procedure ParseParam(sc: TWatScanner; out id: string; out tp: byte; allowIdent: Boolean = true; consumeClose: Boolean = true);
begin
  tp:=0;
  id:='';

  if allowIdent and (sc.token=weIdent) then begin
    id:=sc.resText;
    sc.Next;
  end;

  if not TokenTypeToValType(sc.token, tp) then
    ErrorExpectButFound(sc, WAT_DEFTYPES, TokenStr[sc.token]);

  sc.Next;

  if consumeClose then
    ConsumeToken(sc, weCloseBrace);
end;

procedure ParseNumOrIdx(sc: TWatScanner; out num: integer; out idx: string);
begin
  if sc.token = weIdent then begin
    idx := sc.resText;
    num := -1;
  end else if sc.token = weNumber then begin
    idx := '';
    num := sc.resInt32;
  end else
    ErrorExpectButFound(sc, 'number');
  sc.Next;
end;

procedure ParseInstrList(sc: TWatScanner; dst: TWasmInstrList);
var
  ci  : TWasmInstr;
begin
  while sc.token=weInstr do begin
    sc.Next;
    ci := dst.AddInstr(sc.instrCode);
    case INST_FLAGS[ci.code].Param of
      ipNone:; // do nothing

      ipLeb:
        ParseNumOrIdx(sc, ci.operandNum, ci.operandIdx);

      ipi32,ipi64,ipf32,ipf64:
      begin
        if sc.token<>weNumber then
          ErrorExpectButFound(sc, 'number');
        ci.operandText := sc.resText;
      end;

      //ip2Leb,  // memory arguments, ask for offset + align
      //ipTable,   // a complex structure... used for br_table only
      //ipResType  // result type used for blocks, such as If, block or loop

    end;
  end;

end;

procedure ParseFunc(sc: TWatScanner; dst: TWasmFunc);
var
  nm : integer;
  id : string;
  p  : TWasmParam;
  tk  : TWatToken;
begin
  if sc.token=weFunc then sc.Next;

  if sc.token=weIdent then begin
    dst.id:=sc.resText;
    sc.Next;
  end;

  ConsumeAnyOpenToken(sc, tk);

  if tk = weType then begin
    if not ParseNumOfId(sc, nm, id) then Exit;
    if nm>=0 then dst.functype.typeNum:=nm
    else dst.functype.typeIdx:=id;
    ConsumeAnyOpenToken(sc, tk);
  end;

  while tk = weParam do begin
    p:=dst.functype.AddParam;
    sc.Next;
    ParseParam(sc, p.id, p.tp);
    ConsumeAnyOpenToken(sc, tk);
  end;

  while tk = weResult do begin
    p:=dst.functype.AddResult;
    sc.Next;
    ParseParam(sc, p.id, p.tp, false);
    ConsumeAnyOpenToken(sc, tk);
  end;

  while tk = weLocal do begin
    p:=dst.AddLocal;
    sc.Next;
    ParseParam(sc, p.id, p.tp);
    ConsumeAnyOpenToken(sc, tk);
  end;

  if not (sc.token in [weInstr, weCloseBrace]) then
    ErrorExpectButFound(sc, 'identifier');

  ParseInstrList(sc, dst.instr);
  ConsumeToken(sc, weCloseBrace);
end;

procedure ParseExport(sc: TWatScanner; dst: TWasmExport);
begin
  if sc.token=weExport then
    sc.Next;

  if sc.token<>weString then
    ErrorExpectButFound(sc, 'string');

  dst.name := sc.resWasmString;
  sc.Next;

  ConsumeAnyOpenToken(sc);
  case sc.token of
    weFunc:  dst.exportType:=EXPDESC_FUNC;
    weTable: dst.exportType:=EXPDESC_TABLE;
    weMemory: dst.exportType:=EXPDESC_MEM;
    weGlobal: dst.exportType:=EXPDESC_GLOBAL;
  else
    ErrorExpectButFound(sc, 'func');
  end;

  sc.Next;
  case sc.token of
    weNumber:
      dst.exportNum := sc.resInt32;
    weIdent:
      dst.exportIdx := sc.resText;
  else
    ErrorExpectButFound(sc, 'index');
  end;
  sc.Next;
  ConsumeToken(sc, weCloseBrace);
  ConsumeToken(sc, weCloseBrace);
end;

procedure ParseModuleInt(sc: TWatScanner; dst: TWasmModule);
var
  tk : TWatToken;
begin
  if not ConsumeOpenToken(sc, weModule) then
    ErrorExpectButFound(sc, 'module');

  sc.Next;
  ConsumeAnyOpenToken(sc, tk);
  while tk <> weCloseBrace do begin
    case tk of
      weFunc:
        ParseFunc(sc, dst.AddFunc);
      weExport:
        ParseExport(sc, dst.AddExport);
    else
      ErrorExpectButFound(sc, 'func', TokenStr[sc.token]);
    end;
    ConsumeAnyOpenToken(sc, tk);
  end;
  ConsumeToken(sc, weCloseBrace);
end;

function ParseModule(sc: TWatScanner; dst: TWasmModule; var errMsg: string): Boolean;
var
  res : TParseResult;
begin
  Result := ParseModule(sc, dst, res);
  if not Result then begin
    errMsg:=Format('line: %d, pos: %d, %s', [res.line, res.pos, res.error]);
  end else
    errMsg:='';
end;

procedure GetLineAndPos(const buf: string; ofs: integer; out line, pos: integer);
var
  i: integer;
  ll: integer;
begin
  i:=1;
  line:=1;
  ll:=1;
  while (i<=length(buf)) and (i<ofs) do begin
    if (buf[i]=#13) or (buf[i]=#10) then begin
      inc(line);
      if (i<=length(buf)) and (i<ofs) and ((buf[i]=#13) or (buf[i]=#10)) and (buf[i] <> buf[i-1]) then
        inc(i);
      ll:=i;
    end;
    inc(i);
  end;
  pos:=ofs - ll;
end;

function ParseModule(sc: TWatScanner; dst: TWasmModule; out err: TParseResult): Boolean;
begin
  try
    err.error:='';
    err.pos:=0;
    err.line:=0;
    err.offset:=0;
    ParseModuleInt(sc, dst);
    Result:=true;
  except
    on x: EParserError do begin
      err.error := x.Message;
      err.offset := x.offset;
      GetLineAndPos(sc.buf, x.offset, err.line, err.pos);
      Result:=false;
    end;
  end;
end;

{ EParserError }

constructor EParserError.Create(const amsg: string; aofs: integer);
begin
  inherited Create(amsg);
  offset:=aofs;
end;

end.
