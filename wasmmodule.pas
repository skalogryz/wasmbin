unit wasmmodule;

interface

uses
  Classes, SysUtils, wasmbin, wasmbincode, wasmlink;

type
  TLinkBind = (lbUndefined = 0
               ,lbWeak
               ,lbLocal
               ,lbForHost
               );

  TLinkInfo = record
    Name        : string;
    Binding     : TLinkBind;
    isHidden    : Boolean;
    isUndefined : Boolean;
    NoStrip     : Boolean;
  end;

  TExportInfo = record
    isExport : Boolean;
    name     : string;
  end;

  { TWasmId }

  TWasmId = record
    idNum : integer;
    id    : string;
  end;

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

    // linking information
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
    operandNum  : integer;    // for "call_indirect" this is table index
                              // for "if", "loop", "block" - it's type
    operandText : string;
    insttype    : TWasmFuncType; // used by call_indirect only

    hasRelocIdx : Boolean;
    relocIdx    : integer;
    relocType   : Byte;
    function addInstType: TWasmFuncType;
    constructor Create;
    destructor Destroy; override;
    procedure SetReloc(ARelocType: byte; ARelocIndex: Integer);
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
    LinkInfo : TLinkInfo;
    id       : string;
    idNum    : Integer;     // reference number (after Normalization)
    instr    : TWasmInstrList;
    functype : TWasmFuncType;

    codeRefCount : Integer; // number of times the function was referenced from the code
    constructor Create;
    destructor Destroy; override;
    function AddLocal: TWasmParam;
    function GetLocal(i: integer): TWasmParam;
    function LocalsCount: integer;
  end;

  { TWasmElement }

  TWasmElement = class(TObject)
    tableIdx  : Integer;
    offset    : TWasmInstrList; // offset expression
    funcCount : Integer;
    funcs     : array of TWasmId;
    function AddFunc(idx: integer): integer;
    constructor Create;
    destructor Destroy; override;
  end;

  { TWasmExport }

  TWasmExport = class(TObject)
    name       : string;
    exportType : byte;
    exportNum  : integer;
    exportIdx  : string;
    constructor Create;
  end;

  { TWasmImport }

  TWasmImport = class(TObject)
    LinkInfo : TLinkInfo;
    module   : string;
    name     : string;
    fn       : TWasmFunc;
    function AddFunc: TWasmFunc;
  end;

  { TWasmTable }

  TWasmTable = class(TObject)
    id        : TWasmId;
    elemsType : Byte; // type of elements
    min       : LongWord;
    max       : LongWord;
  end;

  { TWasmModule }

  TWasmModule = class(TObject)
  private
    imports : TList;
    types   : TList;
    funcs   : TList;
    exp     : TList;
    tables  : TList;
    elems   : TList;
  public
    constructor Create;
    destructor Destroy; override;

    function AddTable: TWasmTable;
    function GetTable(i: integer): TWasmTable;
    function TableCount: Integer;

    function AddImport: TWasmImport;
    function GetImport(i: integer): TWasmImport;
    function ImportCount: Integer;

    function AddFunc: TWasmFunc;
    function GetFunc(i: integer): TWasmFunc;
    function FuncCount: integer;

    function AddType: TWasmFuncType;
    function GetType(i: integer): TWasmFuncType;
    function TypesCount: integer;

    function AddExport: TWasmExport;
    function GetExport(i: integer): TWasmExport;
    function ExportCount: integer;

    function AddElement: TWasmElement;
    function GetElement(i: integer): TWasmElement;
    function ElementCount: Integer;
  end;

// making binary friendly. finding proper "nums" for each symbol "index"
// used or implicit type declartions
procedure Normalize(m: TWasmModule);
function WasmBasTypeToChar(b: byte): Char;
function WasmFuncTypeDescr(t: TWasmFuncType): string;

function FindFunc(m: TWasmModule; const funcIdx: string): integer;

// tries to register a function in the module
// the returned value is the offset of the element within the TABLE.
function RegisterFuncIdxInElem(m: TWasmModule; const func: Integer): integer;
function RegisterFuncInElem(m: TWasmModule; const funcId: string): integer;

// tries to get a constant value from instruction list
// right now, it only pulls the first i32_const expression and tries
// to get the value out of it.
// todo: it should be more sophistacated
//
// returns false, if instruction "l" is invalid, or no i32 instruction
function InstrGetConsti32Value(l: TWasmInstrList; var vl: Integer): Boolean;

implementation

// returing a basic wasm basic type to a character
// i32 = i
// i64 = I
// f32 = f
// f64 = F
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

// converting function type to the type string
// result and params are separated by ":"
// iI:i  (param i32)(param i32) (result i32)
// :f    (result f32)
// FF    (param f64)(param(64)
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

// deleting objects from the list and clearing the list
procedure ClearList(l: TList);
var
  i : integer;
begin
  for i:=0 to l.Count-1 do
    TObject(l[i]).Free;
  l.Clear;
end;

{ TWasmElement }

function TWasmElement.AddFunc(idx: integer): integer;
begin
  if funcCount = length(funcs) then begin
    if funcCount=0 then SetLength(funcs, 4)
    else SetLength(funcs, funcCount*2);
  end;
  Result:=funcCount;
  funcs[funcCount].idNum :=idx;
  inc(funcCount);
end;

constructor TWasmElement.Create;
begin
  inherited Create;
  offset := TWasmInstrList.Create;
end;

destructor TWasmElement.Destroy;
begin
  offset.Free;
  inherited Destroy;
end;

{ TWasmImport }

function TWasmImport.AddFunc: TWasmFunc;
begin
  if not Assigned(fn) then fn:= TWasmFunc.Create;
  Result:=fn;
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

constructor TWasmInstr.Create;
begin
  operandNum:=-1;
end;

destructor TWasmInstr.Destroy;
begin
  insttype.Free;
  inherited Destroy;
end;

procedure TWasmInstr.SetReloc(ARelocType: byte; ARelocIndex: Integer);
begin
  hasRelocIdx := true;
  relocType := ARelocType;
  relocIdx := ARelocIndex;
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
  imports := TList.Create;
  tables := TList.Create;
  elems := TList.Create;
end;

destructor TWasmModule.Destroy;
begin
  ClearList(elems);
  elems.Free;
  ClearList(tables);
  tables.Free;
  ClearList(imports);
  imports.Free;
  ClearList(exp);
  exp.Free;
  ClearList(types);
  types.Free;
  ClearList(funcs);
  funcs.Free;
  inherited Destroy;
end;

function TWasmModule.AddTable: TWasmTable;
begin
  Result:=TWasmTable.Create;
  tables.Add(Result);
end;

function TWasmModule.GetTable(i: integer): TWasmTable;
begin
  if (i>=0) and (i<tables.Count) then
    Result:=TWasmTable(tables[i])
  else
    Result:=nil;
end;

function TWasmModule.TableCount: Integer;
begin
  Result:=tables.Count;
end;

function TWasmModule.AddImport: TWasmImport;
begin
  Result:=TWasmImport.Create;
  imports.Add(Result);
end;

function TWasmModule.GetImport(i: integer): TWasmImport;
begin
  if (i>=0) and (i<imports.Count) then
    Result:=TWasmImport(imports[i])
  else
    Result:=nil;
end;

function TWasmModule.ImportCount: Integer;
begin
  Result:=imports.Count;
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

function TWasmModule.AddElement: TWasmElement;
begin
  Result:=TWasmElement.Create;
  elems.add(Result);
end;

function TWasmModule.GetElement(i: integer): TWasmElement;
begin
  if (i>=0) and (i<elems.Count) then
    Result:=TWasmElement(elems[i])
  else
    Result:=nil;
end;

function TWasmModule.ElementCount: Integer;
begin
  Result := elems.Count;
end;

{ TWasmFunc }

constructor TWasmFunc.Create;
begin
  inherited;
  locals:=TList.Create;
  instr:=TWasmInstrList.Create;
  functype:=TWasmFuncType.Create;
  idNum:=-1;
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

function TWasmFunc.GetLocal(i: integer): TWasmParam;
begin
  if (i>=0) and (i<locals.Count) then
    Result:=TWasmParam(locals[i])
  else
    Result:=nil;
end;

function TWasmFunc.LocalsCount: integer;
begin
  result:=locals.Count;
end;

// registering new or finding the existing type for a function type
// it's assumed the function type is explicitly types
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

// searching through TWasmParam list for the specified index-by-name
function FindParam(l: TList; const idx: string): Integer;
var
  i : integer;
begin
  if not Assigned(l) then begin
    Result:=-1;
    Exit;
  end;
  for i:=0 to l.Count-1 do
    if TWasmParam(l[i]).id=idx then begin
      Result:=i;
      Exit;
    end;
  Result:=i;
end;

// finding functions by funcIdx
function FindFunc(m: TWasmModule; const funcIdx: string): integer;
var
  i  : integer;
  im : TWasmImport;
begin
  Result:=-1;
  for i:=0 to m.ImportCount-1 do begin
    im:=m.GetImport(i);
    if Assigned(im.fn) and (im.fn.id = funcIdx) then begin
      Result:=im.fn.idNum;
      Exit;
    end;
  end;

  for i:=0 to m.FuncCount-1 do
    if m.GetFunc(i).id = funcIdx then begin
      Result:=m.GetFunc(i).idNum;
      Exit;
    end;
end;

// only looking up for the by the type index name
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

procedure PopulateRelocData(module: TWasmModule; ci: TWasmInstr);
var
  idx : integer;
begin
  case INST_FLAGS[ci.code].Param of
    ipi32OrFunc:
      if (ci.operandText<>'') and (ci.operandText[1]='$') then begin
        //if not ci.hasRelocIdx then
        idx := RegisterfuncInElem(module, ci.operandText);
        //AddReloc(rt, dst.Position+ofsAddition, idx);
        ci.operandNum := idx;
        ci.SetReloc(INST_RELOC_FLAGS[ci.code].relocType, idx);
      end;

    ipLeb:
       if (INST_RELOC_FLAGS[ci.code].doReloc) then begin
         ci.SetReloc(INST_RELOC_FLAGS[ci.code].relocType, ci.operandNum);
       end;

    ipCallType:
      if Assigned(ci.insttype) then
        ci.SetReloc(INST_RELOC_FLAGS[ci.code].relocType, ci.insttype.typeNum);
  end;
end;

// Normalizing instruction list, popuplating index reference ($index)
// with the actual numbers. (params, locals, globals, memory, functions index)
procedure NormalizeInst(m: TWasmModule; f: TWasmFunc; l: TWasmInstrList; checkEnd: boolean = true);
var
  i   : integer;
  j   : integer;
  ci  : TWasmInstr;
  endNeed : Integer;
const
  ValidResTypes = [VALTYPE_NONE,VALTYPE_I32,VALTYPE_I64,VALTYPE_F32,VALTYPE_F64];
begin
  endNeed := 1;
  for i:=0 to l.Count-1 do begin
    ci:=l[i];

    if INST_FLAGS[ci.code].Param = ipResType then
    begin
      inc(endNeed);
      if not byte(ci.operandNum) in ValidResTypes then
        ci.operandNum := VALTYPE_NONE;
    end;

    case ci.code of
      INST_local_get, INST_local_set, INST_local_tee:
      begin
        if (ci.operandIdx<>'') and (ci.operandNum<0) then begin
          j:=FindParam(f.functype.params, ci.operandIdx);
          if j<0 then begin
            j:=FindParam(f.locals, ci.operandIdx);
            if j>=0 then inc(j, f.functype.ParamCount);
          end;
          ci.operandNum:=j;
        end;
      end;

      INST_call:
      begin
        if (ci.operandIdx<>'') and (ci.operandNum<0) then
          ci.operandNum:=FindFunc(m,ci.operandIdx);
      end;

      INST_call_indirect:
      begin
        if Assigned(ci.insttype) and (ci.insttype.typeNum<0) then
          ci.insttype.typeNum:=RegisterFuncType(m, ci.insttype);
      end;

      INST_END: dec(endNeed);
    end;

    PopulateRelocData(m, ci);
  end;

  // adding end instruction
  if checkEnd and (endNeed>0) then
    l.AddInstr(INST_END);
end;


procedure NormalizeFuncType(m: TWasmModule; fn : TWasmFuncType);
begin
  if fn.isNumOrIdx then begin
    if fn.typeIdx<>'' then
      fn.typeNum:=FindFuncType(m, fn.typeIdx);
  end else
    fn.typeNum:=RegisterFuncType(m, fn);
end;

procedure NormalizeImport(m: TWasmModule; var fnIdx: Integer);
var
  i  : integer;
  im : TWasmImport;
begin
  fnIdx := 0;
  for i:=0 to m.ImportCount-1 do begin
    im := m.GetImport(i);
    if Assigned(im.fn) then begin
      im.fn.idNum:=fnIdx;
      NormalizeFuncType(m, im.fn.functype);
      inc(fnIdx);
    end;
  end;
end;

// normalizing reference
procedure Normalize(m: TWasmModule);
var
  i     : integer;
  f     : TWasmFunc;
  x     : TWasmExport;
  fnIdx : Integer;
begin
  fnIdx := 0;
  NormalizeImport(m, fnIdx);

  for i:=0 to m.FuncCount-1 do begin
    f:=m.GetFunc(i);
    f.idNum := fnIdx;

    NormalizeFuncType(m, f.functype);
    // finding the reference in functions
    // populating "nums" where string "index" is used
    NormalizeInst(m, f, f.instr);

    inc(fnIdx);
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

function RegisterFuncIdxInElem(m: TWasmModule; const func: Integer): integer;
var
  el : TWasmElement;
  i  : Integer;
  ofs : Integer;
const
  NON_ZEROFFSET = 1; // being compliant with Linking convention
  // The output table elements shall begin at a non-zero offset within
  // the table, so that a call_indirect 0 instruction is guaranteed to fail.
  // Finally, when processing table relocations for symbols which
  // have neither an import nor a definition (namely, weakly-undefined
  // function symbols), the value 0 is written out as the value of the relocation.
  NON_ZEROFFSET_STR = '1';
begin
  if m.ElementCount=0 then begin
    el := m.AddElement;
    el.offset.AddInstr(INST_i32_const).operandText:=NON_ZEROFFSET_STR;
    el.offset.AddInstr(INST_END);
  end else
    el := m.GetElement(0);

  if not InstrGetConsti32Value(el.offset, ofs) then ofs := 0;

  Result:=-1;
  for i:=0 to el.funcCount-1 do begin
    if el.funcs[i].idNum = func then
      Result:=i;
  end;
  if Result<0 then
    Result := el.AddFunc(func);

  Result := Result + ofs;
end;

function RegisterFuncInElem(m: TWasmModule; const funcId: string): integer;
var
  fnidx : integer;
begin
  fnidx := FindFunc(m, funcId);
  if fnidx>=0 then
    Result := RegisterFuncIdxInElem(m, fnidx)
  else
    Result := -1;
end;

function InstrGetConsti32Value(l: TWasmInstrList; var vl: Integer): Boolean;
var
  err : integer;
begin
  //todo: it must be more complicated than that
  Result:=Assigned(l) and (l.Count>0) and (l.Item[0].code = INST_i32_const);
  if not Result then Exit;

  Val(l.Item[0].operandText, vl, err);
  Result := err = 0;
end;

end.
