program igapack;

{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Windows, System.SysUtils, System.Classes;

{$SETPEFLAGS IMAGE_FILE_RELOCS_STRIPPED}

function GetFileSize(const aFilename: String): Int64;
var
  info: TWin32FileAttributeData;
begin
  result:=-1;
  if not GetFileAttributesEx(PWideChar(aFileName), GetFileExInfoStandard, @info) then exit;
  result:=info.nFileSizeLow or (info.nFileSizeHigh shl 32);
end;

function GetMultibyte(InputStream: TStream): LongWord;
var
  Byte1: Byte;
begin
  Result:=0;
  while Byte(Result and 1)=0 do
  begin
    InputStream.ReadBuffer(Byte1,1);
    Result:=Result shl 7 or Byte1;
  end;
  Result:=Result shr 1;
end;

procedure EncMultibyte(LongWord1: LongWord; OutputStream: TStream);
var
  Byte1: Byte;
begin
  LongWord1:=LongWord1 shl 1;

  if LongWord1 shr 28>1 then begin Byte1:=Byte(LongWord1 shr 29 shl 1); OutputStream.WriteBuffer(Byte1,1) end;
  if LongWord1 shr 21>1 then begin Byte1:=Byte(LongWord1 shr 22 shl 1); OutputStream.WriteBuffer(Byte1,1) end;
  if LongWord1 shr 14>1 then begin Byte1:=Byte(LongWord1 shr 15 shl 1); OutputStream.WriteBuffer(Byte1,1) end;
  if LongWord1 shr 7>1 then begin Byte1:=Byte(LongWord1 shr 8 shl 1); OutputStream.WriteBuffer(Byte1,1) end;

  Byte1:=Byte(LongWord1) or 1;
  OutputStream.WriteBuffer(Byte1,1);
end;

procedure Unpack;
var
  FileStream1: TFileStream;
  MemoryStream1, MemoryStream2, MemoryStream3: TMemoryStream;
  i, x: Integer;
  Byte1: Byte;
  LongWord1, DataBlockPos, FileCount, FilenamePos, DataPos, DataSize, FilenameEnd: LongWord;
  s, FileDirOut: String;
  StringList1: TStringList;
begin
  try
    FileDirOut:=ExpandFileName(Copy(ParamStr(1),1,Length(ParamStr(1))-Length(ExtractFileExt(ParamStr(1)))));
    FileStream1:=TFileStream.Create(ParamStr(1), fmOpenRead or fmShareDenyWrite); MemoryStream1:=TMemoryStream.Create; MemoryStream2:=TMemoryStream.Create;
    try
      FileStream1.ReadBuffer(LongWord1,4);
      if not (LongWord1=$30414749) then begin Writeln('Error: Input file is not a valid Innocent Grey Archive file.'); Readln; exit end;


      FileStream1.Position:=$10;
      LongWord1:=GetMultibyte(FileStream1); //EntryTableLength
      MemoryStream2.CopyFrom(FileStream1, LongWord1);
      MemoryStream2.Position:=0;
      repeat
        for i:=1 to 3 do begin LongWord1:=GetMultibyte(MemoryStream2); MemoryStream1.WriteBuffer(LongWord1,4) end; //FilenamePos, DataPos, DataSize
      until MemoryStream2.Position=MemoryStream2.Size;
      FileCount:=MemoryStream1.Size div 12;

      LongWord1:=GetMultibyte(FileStream1); //FilenamesLength
      DataBlockPos:=LongWord1+FileStream1.Position; //FilenamesLength + data before it
      MemoryStream2.Clear;
      MemoryStream2.CopyFrom(FileStream1, LongWord1);

      FileStream1.Position:=4;
      FileStream1.ReadBuffer(LongWord1,4);
      if not (DirectoryExists(FileDirOut)) then CreateDir(FileDirOut);
      MemoryStream1.Position:=0;
      StringList1:=TStringList.Create;
      try
        FileStream1.Position:=4;
        FileStream1.ReadBuffer(LongWord1,4);
        StringList1.Add('['+IntToStr(LongWord1)+']');
        for i:=1 to FileCount do
        begin
          MemoryStream1.ReadBuffer(FilenamePos,4);
          MemoryStream1.ReadBuffer(DataPos,4);
          MemoryStream1.ReadBuffer(DataSize,4);
          if MemoryStream1.Position+4 < MemoryStream1.Size then begin MemoryStream1.ReadBuffer(FilenameEnd,4); MemoryStream1.Position:=MemoryStream1.Position-4 end else FilenameEnd:=MemoryStream2.Size;

          s:='';
          MemoryStream2.Position:=FilenamePos;
          for x:=1 to FilenameEnd-FilenamePos do
          begin
            s:=s+Char(GetMultibyte(MemoryStream2));
          end;
          StringList1.Add(s);

          FileStream1.Position:=DataBlockPos+DataPos;
          MemoryStream3:=TMemoryStream.Create;
          try
            MemoryStream3.CopyFrom(FileStream1, DataSize);
            MemoryStream3.Position:=0;
            for x:=0 to MemoryStream3.Size-1 do
            begin
              MemoryStream3.ReadBuffer(Byte1,1);
              Byte1:=Byte1 xor Byte(x+2);
              MemoryStream3.Position:=MemoryStream3.Position-1;
              MemoryStream3.WriteBuffer(Byte1,1);
            end;
            MemoryStream3.SaveToFile(FileDirOut+'\'+s);
            Writeln('[',StringOfChar('0',Length(IntToStr(FileCount))-Length(IntToStr(i)))+IntToStr(i)+'/'+IntToStr(FileCount)+'] '+s);
          finally MemoryStream3.Free end;
        end;
        StringList1.SaveToFile(FileDirOut+'\'+'iga_filelist.txt', TEncoding.UTF8);
      finally StringList1.Free end;
    finally FileStream1.Free; MemoryStream1.Free; MemoryStream2.Free end;
  except on E: Exception do begin Writeln('Error: '+E.Message); Readln; exit end end;
end;

procedure Pack;
var
  InputDir, s: String;
  z, i: Integer;
  FileStream1, FileStream2: TFileStream;
  MemoryStream1, MemoryStream2: TMemoryStream;
  LongWord1, FilenamePos, DataPos, DataSize: LongWord;
  Byte1: Byte;
  StringList1: TStringList;
begin
  try
    InputDir:=ExpandFileName(ParamStr(1));
    repeat if InputDir[Length(InputDir)]='\' then SetLength(InputDir, Length(InputDir)-1) until not (InputDir[Length(InputDir)]='\');
    if not (FileExists(InputDir+'\iga_filelist.txt')) then begin Writeln('Error: iga_filelist.txt not found in selected directory.'); Readln; exit end;

    FileStream1:=TFileStream.Create(InputDir+'.iga', fmCreate or fmOpenWrite or fmShareDenyWrite); MemoryStream1:=TMemoryStream.Create; StringList1:=TStringList.Create;
    try
      StringList1.LoadFromFile(InputDir+'\iga_filelist.txt');
      LongWord1:=$30414749;
      FileStream1.WriteBuffer(LongWord1,4);
      LongWord1:=StrToInt64(Copy(StringList1[0],2,Length(StringList1[0])-2));
      FileStream1.WriteBuffer(LongWord1,4);
      LongWord1:=2;
      FileStream1.WriteBuffer(LongWord1,4);
      FileStream1.WriteBuffer(LongWord1,4);
      FilenamePos:=0; DataPos:=0;

      MemoryStream2:=TMemoryStream.Create;
      try
        for z:=1 to StringList1.Count-1 do
        begin
          s:=StringList1[z];

          for i:=1 to Length(s) do
          begin
            Byte1:=Ord(s[i]) shl 1 or 1;
            MemoryStream2.WriteBuffer(Byte1,1);
          end;

          EncMultibyte(FilenamePos, MemoryStream1);
          FilenamePos:=FilenamePos+Length(s);
          EncMultibyte(DataPos, MemoryStream1);
          DataSize:=GetFileSize(InputDir+'\'+StringList1[z]);
          DataPos:=DataPos+DataSize;
          EncMultibyte(DataSize, MemoryStream1);
        end;
        EncMultibyte(MemoryStream1.Size, FileStream1);
        MemoryStream1.Position:=0;
        FileStream1.CopyFrom(MemoryStream1,MemoryStream1.Size);
        EncMultibyte(FilenamePos, FileStream1);
        MemoryStream2.Position:=0;
        FileStream1.CopyFrom(MemoryStream2,MemoryStream2.Size);
      finally MemoryStream2.Free end;

      for z:=1 to StringList1.Count-1 do
      begin
        FileStream2:=TFileStream.Create(InputDir+'\'+StringList1[z], fmOpenRead or fmShareDenyWrite);
        try
          MemoryStream1.Position:=0;
          MemoryStream1.CopyFrom(FileStream2, FileStream2.Size);
          MemoryStream1.Position:=0;
          for i:=0 to FileStream2.Size-1 do
          begin
            MemoryStream1.ReadBuffer(Byte1,1);
            Byte1:=Byte1 xor Byte(i+2);
            MemoryStream1.Position:=MemoryStream1.Position-1;
            MemoryStream1.WriteBuffer(Byte1,1);
          end;
          MemoryStream1.Position:=0;
          FileStream1.CopyFrom(MemoryStream1, FileStream2.Size);
          Writeln('[',StringOfChar('0',Length(IntToStr(StringList1.Count-1))-Length(IntToStr(z)))+IntToStr(z)+'/'+IntToStr(StringList1.Count-1)+'] '+StringList1[z]);
        finally FileStream2.Free end;
      end;
    finally FileStream1.Free; MemoryStream1.Free; StringList1.Free end;
  except on E: Exception do begin Writeln('Error: '+E.Message); Readln; exit end end;
end;

begin
  try
    Writeln('Innocent Grey Archive Unpacker/Packer v1.0 by RikuKH3');
    Writeln('-----------------------------------------------------');
    if ParamCount<1 then begin Writeln('Usage: igapack.exe input_file_or_folder'); Readln; exit end;
    if UpperCase(ExtractFileExt(ParamStr(1)))='.IGA' then Unpack else Pack;
  except on E: Exception do begin Writeln('Error: '+E.Message); Readln; exit end end;
end.
