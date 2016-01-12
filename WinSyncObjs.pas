unit WinSyncObjs;

interface

uses
  Windows; 

type
  TCriticalSection = class(TObject)
  private
    fCriticalSectionObj:  TRTLCriticalSection;
    fSpinCount:           DWORD;
    procedure _SetSpinCount(Value: DWORD);
  public
    constructor Create; overload;
    constructor Create(SpinCount: DWORD); overload;
    destructor Destroy; override;
    Function SetSpinCount(SpinCount: DWORD): DWORD;
    Function TryEnter: Boolean;
    procedure Enter;
    procedure Leave;
    property SpinCount: DWORD read fSpinCount write _SetSpinCount;
  end;

  TWinSyncObject = class(TObject)
  private
    fHandle:      THandle;
    fLastError:   Integer;
    fName:        String;
  public
    destructor Destroy; override;
    property Handle: THandle read fHandle;
    property LastError: Integer read fLastError;
    property Name: String read fName;
  end;

implementation

procedure TCriticalSection._SetSpinCount(Value: DWORD);
begin
fSpinCount := Value;
SetSpinCount(fSpinCount);
end;

//------------------------------------------------------------------------------

constructor TCriticalSection.Create;
begin
inherited Create;
fSpinCount := 0;
InitializeCriticalSection(fCriticalSectionObj);
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TCriticalSection.Create(SpinCount: DWORD);
begin
inherited Create;
fSpinCount := SpinCount;
InitializeCriticalSectionAndSpinCount(fCriticalSectionObj,SpinCount);
end;

//------------------------------------------------------------------------------

destructor TCriticalSection.Destroy;
begin
DeleteCriticalSection(fCriticalSectionObj);
inherited;
end;

//------------------------------------------------------------------------------

Function TCriticalSection.SetSpinCount(SpinCount: DWORD): DWORD;
begin
fSpinCount := SpinCount;
Result := SetCriticalSectionSpinCount(fCriticalSectionObj,SpinCount);
end;

//------------------------------------------------------------------------------

Function TCriticalSection.TryEnter: Boolean;
begin
Result := TryEnterCriticalSection(fCriticalSectionObj);
end;

//------------------------------------------------------------------------------

procedure TCriticalSection.Enter;
begin
EnterCriticalSection(fCriticalSectionObj);
end;

//------------------------------------------------------------------------------

procedure TCriticalSection.Leave;
begin
LeaveCriticalSection(fCriticalSectionObj);
end;

//==============================================================================

destructor TWinSyncObject.Destroy;
begin
CloseHandle(fHandle);
inherited;
end;

end.

