program wasa;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, watparser, watscanner, wasmmodule, wasmbinwriter,
  wasmnormalize;

type
  TAsmParams = record
    SrcFile    : string;
    Reloc      : Boolean;
    DstObjFile : string;
  end;

procedure DefaultParams(out p: TAsmParams);
begin
  p.SrcFile := '';
  p.Reloc := false;
  p.DstObjFile := '';
end;

procedure WriteBin(const p: TAsmParams; m: TWasmModule);
var
  f : TFileStream;
begin
  f := TFileStream.Create(p.DstObjFile, fmCreate);
  try
    Normalize(m);
    WriteModule(m, f, p.Reloc, p.Reloc);
  finally
    f.Free;
  end;
end;

procedure Run(const prm: TAsmParams);
var
  st : TFileStream;
  s  : string;
  p  : TWatScanner;
  m  : TWasmModule;
  err : string;
begin
  st := TFileStream.Create(prm.SrcFile, fmOpenRead or fmShareDenyNone);
  p := TWatScanner.Create;
  try
    SetLength(s, st.Size);
    if length(s)>0 then st.Read(s[1], length(s));
    p.SetSource(s);
    m := TWasmModule.Create;
    try
      if not ParseModule(p, m, err) then
        writeln('Error: ', err)
      else
        WriteBin(prm, m);
    finally
      m.Free;
    end;
  finally
    p.Free;
    st.Free;
  end;
end;

procedure ParseParams(var p: TAsmParams);
var
  i : integer;
  s : string;
  ls : string;
begin
  i:=1;
  while i<=ParamCount do begin
    s := ParamStr(i);
    if (s<>'') and (s[1]='-') then begin
      ls := AnsiLowerCase(s);
      if ls = '-o' then begin
        inc(i);
        if (i<=ParamCount) then
          p.DstObjFile:=ParamStr(i);
      end else if ls = '-r' then
        p.Reloc := true;
    end else
      p.SrcFile := s;
    inc(i);
  end;

  if (p.SrcFile<>'') then begin
    p.SrcFile := ExpandFileName(p.SrcFile);
    if (p.DstObjFile = '') then
      p.DstObjFile := ChangeFileExt(p.SrcFile, '.wasm')
  end;
end;

var
  prm  : TAsmParams;
begin
  DefaultParams(prm);
  ParseParams(prm);
  if (prm.SrcFile='') then begin
    writeln('please specify the input .wat file');
    exit;
  end;
  if not FileExists(prm.SrcFile) then begin
    writeln('file doesn''t exist: ', prm.SrcFile);
    exit;
  end;

  try
    Run(prm);
  except
    on e: exception do
      writeln(e.message);
  end
end.

