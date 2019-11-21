unit wasmmodule;

interface

uses
  Classes, SysUtils, wasmbin;

type

  { TWasmParam }

  TWasmParam = class(TObject)
    id : string;
    tp : byte;
    procedure CopyTo(d: TWasmParam);
  end;

  { TWasmType }

  // function signature

  { TWasmFuncType }

  TWasmFuncType = class(TObject)
  private
    params  : TList;
    results : TList;
  public
    typeNum : Integer; // if Idx < 0 then type is declared from typeDef
    typeIdx : string;  // if typeID='' then type is declared from typeDef
    constructor Create;
    destructor Destroy; override;
    function AddResult(tp: byte = 0): TWasmParam;
    function AddParam(tp: byte = 0; const id: string = ''): TWasmParam;
    function GetParam(i: integer): TWasmParam;
    function GetResult(i: integer): TWasmParam; overload;
    function GetResult: TWasmParam;  overload;
    function ResultCount: Integer;
    function ParamCount: Integer;

    function isNumOrIdx: Boolean;

    procedure CopyTo(t: TWasmFuncType);
  end;

  { TWasmInstr }

  TWasmInstr = class(TObject)
    code        : byte;
    operandIdx  : string;
    operandNum  : integer;
    operandText : string;
    insttype : TWasmFuncType; // used by call_indirect only
    function addInstType: TWasmFuncType;
    destructor Destroy; override;
  end;

  { TWasmInstrList }

  TWasmInstrList = class(TObject)
  private
    items: TList;
    function GetItem(i: integer): TWasmInstr;
  public
    constructor Create;
    destructor Destroy; override;
    function AddInstr(acode: byte = 0): TWasmInstr;
    function Count: Integer;
    property Item[i: integer]: TWasmInstr read GetItem; default;
  end;

  { TWasmFunc }

  TWasmFunc = class(TObject)
  private
    locals:  TList;
  public
    id : string;
    instr    : TWasmInstrList;
    functype : TWasmFuncType;
    constructor Create;
    destructor Destroy; override;
    function AddLocal: TWasmParam;
    function LocalsCount: integer;
  end;

  { TWasmExport }

  TWasmExport = class(TObject)
    name       : string;
    exportType : byte;
    exportNum  : integer;
    exportIdx  : string;
    constructor Create;
  end;

  { TWasmModule }

  TWasmModule = class(TObject)
  private
    types   : TList;
    funcs   : TList;
    exp     : TList;
  public
    constructor Create;
    destructor Destroy; override;

    function AddFunc: TWasmFunc;
    function GetFunc(i: integer): TWasmFunc;
    function FuncCount: integer;

    function AddType: TWasmFuncType;
    function GetType(i: integer): TWasmFuncType;
    function TypesCount: integer;

    function AddExport: TWasmExport;
    function GetExport(i: integer): TWasmExport;
    function ExportCount: integer;
  end;

// making binary friendly. finding proper "nums" for each symbol "index"
// used or implicit type declartions
procedure Normalize(m: TWasmModule);
//function RegisterFuncType(m: TWasmModule; funcType: TFuncType): integer;
function WasmBasTypeToChar(b: byte): Char;
function WasmFuncTypeDescr(t: TWasmFuncType): string;

implementation

function WasmBasTypeToChar(b: byte): Char;
begin
  case b of
    valtype_i32: Result:='i';
    valtype_i64: Result:='I';
    valtype_f32: Result:='f';
    valtype_f64: Result:='F';
  else
    Result:='.';
  end;
end;

function WasmFuncTypeDescr(t: TWasmFuncType): string;
var
  cnt   : integer;
  i : integer;
  j : integer;
begin
  cnt:=t.ParamCount;
  if t.Resultcount>0 then inc(cnt, t.ResultCount+1);
  SetLength(Result, cnt);
  if cnt=0 then Exit;

  j:=1;
  for i:=0 to t.ParamCount-1 do begin
    Result[j]:=WasmBasTypeToChar(t.GetParam(i).tp);
    inc(j);
  end;

  if t.ResultCount=0 then Exit;

  Result[j]:=':';
  inc(j);
  for i:=0 to t.ResultCount-1 do begin
    Result[j]:=WasmBasTypeToChar(t.GetResult(i).tp);
    inc(j);
  end;
end;


procedure ClearList(l: TList);
var
  i : integer;
begin
  for i:=0 to l.Count-1 do
    TObject(l[i]).Free;
  l.Clear;
end;

{ TWasmExport }

constructor TWasmExport.Create;
begin
  inherited Create;
  exportNum:=-1;
end;

{ TWasmParam }

procedure TWasmParam.CopyTo(d: TWasmParam);
begin
  d.tp:=tp;
end;

{ TWasmInstr }

function TWasmInstr.addInstType: TWasmFuncType;
begin
  if insttype=nil then insttype := TWasmFuncType.Create;
  result:=insttype;
end;

destructor TWasmInstr.Destroy;
begin
  insttype.Free;
  inherited Destroy;
end;

{ TWasmInstrList }

function TWasmInstrList.GetItem(i: integer): TWasmInstr;
begin
  if (i>=0) and (i < items.Count) then
    Result:=TWasmInstr(items[i])
  else
    Result:=nil;
end;

constructor TWasmInstrList.Create;
begin
  inherited Create;
  items:=TList.Create;
end;

destructor TWasmInstrList.Destroy;
begin
  ClearList(items);
  items.Free;
  inherited Destroy;
end;

function TWasmInstrList.AddInstr(acode: byte = 0): TWasmInstr;
begin
  Result:=TWasmInstr.Create;
  Result.code:=acode;
  items.Add(Result);
end;

function TWasmInstrList.Count: Integer;
begin
  Result:=items.Count;
end;

{ TWasmFuncType }

constructor TWasmFuncType.Create;
begin
  inherited Create;
  typeNum:=-1;
  params:=Tlist.Create;
  results:=Tlist.Create;
end;

destructor TWasmFuncType.Destroy;
begin
  ClearList(params);
  ClearList(results);
  params.free;
  results.free;
  inherited Destroy;
end;

function TWasmFuncType.AddResult(tp: byte): TWasmParam;
begin
  Result:=TWasmParam.Create;
  Result.tp:=tp;
  results.Add(Result);
end;

function TWasmFuncType.AddParam(tp: byte; const id: string): TWasmParam;
begin
  Result:=TWasmParam.Create;
  Result.tp:=tp;
  Result.id:=id;
  params.Add(Result);
end;

function TWasmFuncType.GetParam(i: integer): TWasmParam;
begin
  if (i>=0) and (i<params.Count) then
    Result:=TWasmParam(params[i])
  else
    Result:=nil;
end;

function TWasmFuncType.GetResult(i: integer): TWasmParam;
begin
  if (i>=0) and (i<results.Count) then
    Result:=TWasmParam(results[i])
  else
    Result:=nil;
end;

function TWasmFuncType.GetResult: TWasmParam;
begin
  Result:=GetResult(0);
end;

function TWasmFuncType.ResultCount: Integer;
begin
  Result:=results.Count;
end;

function TWasmFuncType.ParamCount: Integer;
begin
  Result:=params.Count;
end;

function TWasmFuncType.isNumOrIdx: Boolean;
begin
  Result:=(typeIdx<>'') or (typeNum>=0);
end;

procedure TWasmFuncType.CopyTo(t: TWasmFuncType);
var
  i : integer;
  s : TWasmParam;
  d : TWasmParam;
begin
  for i:=0 to ParamCount-1 do begin
    d := t.AddParam;
    s := GetParam(i);
    s.CopyTo(d);
  end;

  for i:=0 to ResultCount-1 do begin
    d := t.AddResult;
    s := GetResult(i);
    s.CopyTo(d);
  end;
end;

{ TWasmModule }

constructor TWasmModule.Create;
begin
  inherited Create;
  types := TList.Create;
  funcs := TList.Create;
  exp := TList.Create;
end;

destructor TWasmModule.Destroy;
begin
  ClearList(exp);
  exp.Free;
  ClearList(types);
  types.Free;
  ClearList(funcs);
  funcs.Free;
  inherited Destroy;
end;

function TWasmModule.AddFunc: TWasmFunc;
begin
  Result:=TWasmFunc.Create;
  funcs.Add(Result);
end;

function TWasmModule.AddType: TWasmFuncType;
begin
  Result:=TWasmFuncType.Create;
  types.Add(Result);
end;

function TWasmModule.GetFunc(i: integer): TWasmFunc;
begin
  if (i>=0) and (i<funcs.Count) then
    Result:=TWasmFunc(funcs[i])
  else
    Result:=nil;
end;

function TWasmModule.FuncCount: integer;
begin
  Result:=funcs.Count;
end;

function TWasmModule.GetType(i: integer): TWasmFuncType;
begin
  if (i>=0) and (i<types.Count) then
    Result:=TWasmFuncType(types[i])
  else
    Result:=nil;
end;

function TWasmModule.TypesCount: integer;
begin
  Result:=types.Count;
end;

function TWasmModule.AddExport: TWasmExport;
begin
  Result:=TWasmExport.Create;
  exp.add(Result);
end;

function TWasmModule.GetExport(i: integer): TWasmExport;
begin
  if (i>=0) and (i<exp.Count) then
    Result:=TWasmExport(exp[i])
  else
    Result:=nil;
end;

function TWasmModule.ExportCount: integer;
begin
  Result:=exp.Count;
end;

{ TWasmFunc }

constructor TWasmFunc.Create;
begin
  inherited;
  locals:=TList.Create;
  instr:=TWasmInstrList.Create;
  functype:=TWasmFuncType.Create;
end;

destructor TWasmFunc.Destroy;
begin
  ClearList(locals);
  locals.Free;
  functype.Free;
  instr.Free;
  inherited Destroy;
end;

function TWasmFunc.AddLocal: TWasmParam;
begin
  Result:=TWasmParam.Create;
  locals.AdD(Result);
end;

function TWasmFunc.LocalsCount: integer;
begin
  result:=locals.Count;
end;


function RegisterFuncType(m: TWasmModule; funcType: TWasmFuncType): integer;
var
  i   : integer;
  trg : string;
  d   : string;
begin
  trg := WasmFuncTypeDescr(funcType);
  for i:=0 to m.TypesCount-1 do begin
    d := WasmFuncTypeDescr(m.GetType(i));
    if trg = d then begin
      Result:= i;
      Exit;
    end;
  end;
  Result:=m.TypesCount;
  funcType.CopyTo(m.AddType);
end;

function FindFunc(m: TWasmModule; const funcIdx: string): integer;
var
  i : integer;
begin
  Result:=-1;
  for i:=0 to m.FuncCount-1 do
    if m.GetFunc(i).id = funcIdx then begin
      Result:=i;
      Exit;
    end;
end;

function FindFuncType(m: TWasmModule; const typeIdx: string): integer;
var
  i : integer;
begin
  Result:=-1;
  for i:=0 to m.TypesCount-1 do
    if m.GetType(i).typeIdx = typeIdx then begin
      Result:=i;
      Exit;
    end;
end;

procedure Normalize(m: TWasmModule);
var
  i : integer;
  f : TWasmFunc;
  x : TWasmExport;
begin
  for i:=0 to m.FuncCount-1 do begin
    f:=m.GetFunc(i);
    if f.functype.isNumOrIdx then begin
      if f.functype.typeIdx<>'' then
        f.functype.typeNum:=FindFuncType(m, f.functype.typeIdx);
    end else
      f.functype.typeNum:=RegisterFuncType(m, f.functype)
  end;

  // normalizing exports
  for i:=0 to m.ExportCount-1 do begin
    x:=m.GetExport(i);
    if x.exportNum<0 then
      case x.exportType of
        EXPDESC_FUNC:
          if x.exportIdx<>'' then
            x.exportNum := FindFunc(m, x.exportIdx);
      end;
  end;
end;

end.
