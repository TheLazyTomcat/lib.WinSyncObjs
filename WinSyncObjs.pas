{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  WinSyncObjs

    Set of classes encapsulating windows synchronization objects.

  Version 1.2 (2021-09-25)

  Last change 2021-09-25

  ©2016-2021 František Milt

  Contacts:
    František Milt: frantisek.milt@gmail.com

  Support:
    If you find this code useful, please consider supporting its author(s) by
    making a small donation using the following link(s):

      https://www.paypal.me/FMilt

  Changelog:
    For detailed changelog and history please refer to this git repository:

      github.com/TheLazyTomcat/Lib.WinSyncObjs

  Dependencies:
    AuxTypes    - github.com/TheLazyTomcat/Lib.AuxTypes
    AuxClasses  - github.com/TheLazyTomcat/Lib.AuxClasses
    StrRect     - github.com/TheLazyTomcat/Lib.StrRect

===============================================================================}
unit WinSyncObjs;

{$IF not(defined(MSWINDOWS) or defined(WINDOWS))}
  {$MESSAGE FATAL 'Unsupported operating system.'}
{$IFEND}

{$IFDEF FPC}
  {$MODE Delphi}
  {$INLINE ON}
  {$DEFINE CanInline}
  {$DEFINE FPC_DisableWarns}
  {$MACRO ON}
{$ELSE}
  {$IF CompilerVersion >= 17 then}  // Delphi 2005+
    {$DEFINE CanInline}
  {$ELSE}
    {$UNDEF CanInline}
  {$IFEND}
{$ENDIF}
{$H+}

{$IF Declared(CompilerVersion)}
  {$IF CompilerVersion >= 20} // Delphi 2009+
    {$DEFINE DeprecatedCommentDelphi}
  {$IFEND}
{$IFEND}

{$IF Defined(FPC) or Defined(DeprecatedCommentDelphi)}
  {$DEFINE DeprecatedComment}
{$ELSE}
  {$UNDEF DeprecatedComment}
{$IFEND}

interface

uses
  Windows, SysUtils,
  AuxClasses;

const
  SEMAPHORE_MODIFY_STATE = $00000002;
  SEMAPHORE_ALL_ACCESS   = STANDARD_RIGHTS_REQUIRED or SYNCHRONIZE or $3;

  TIMER_MODIFY_STATE = $00000002;
  TIMER_QUERY_STATE  = $00000001;
  TIMER_ALL_ACCESS   = STANDARD_RIGHTS_REQUIRED or SYNCHRONIZE or
                       TIMER_QUERY_STATE or TIMER_MODIFY_STATE;

type
  TWaitResult = (wrSignaled, wrAbandoned, wrIOCompletion, wrMessage, wrTimeout, wrError);

  // library-specific exceptions
  EWSOException = class(Exception);

  EWSOTimeConversionError    = class(EWSOException);
  EWSOMultiWaitInvalidCount  = class(EWSOException);
  EWSOWaitError              = class(EWSOException);
  EWSOInvalidHandle          = class(EWSOException);
  EWSOHandleDuplicationError = class(EWSOException);

{===============================================================================
--------------------------------------------------------------------------------
                                TCriticalSection
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TCriticalSection - class declaration
===============================================================================}
type
  TCriticalSection = class(TCustomObject)
  private
    fCriticalSectionObj:  TRTLCriticalSection;
    fSpinCount:           DWORD;
    procedure SetSpinCountProc(Value: DWORD); // only redirector to SetSpinCount (setter cannot be a function)
  public
    constructor Create; overload;
    constructor Create(SpinCount: DWORD); overload;
    destructor Destroy; override;
    Function SetSpinCount(SpinCount: DWORD): DWORD;
    Function TryEnter: Boolean;
    procedure Enter;
    procedure Leave;
    property SpinCount: DWORD read fSpinCount write SetSpinCountProc;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                 TWinSyncObject                                 
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TWinSyncObject - class declaration
===============================================================================}
type
  TWinSyncObject = class(TCustomObject)
  protected
    fLastError: DWORD;
    fName:      String;
    Function SetAndRectifyName(const Name: String): Boolean; virtual;
  public
    constructor Create;
  {
    LastError stores code of the last operating system error that has not
    resulted in an exception being raised (eg. error during waiting).
  }
    property LastError: DWORD read fLastError;
    property Name: String read fName;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                              TComplexWinSyncObject
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TComplexWinSyncObject - class declaration
===============================================================================}
type
  TComplexWinSyncObject = class(TCustomObject)
  protected
    fProcessShared: Boolean;
  public
    property ProcessShared: Boolean read fProcessShared;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                              TSimpleWinSyncObject
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSimpleWinSyncObject - class declaration
===============================================================================}
type
  TSimpleWinSyncObject = class(TWinSyncObject)
  protected
    fHandle:  THandle;
    Function SetAndRectifyName(const Name: String): Boolean; override;
    procedure SetAndCheckHandle(Handle: THandle); virtual;
    procedure DuplicateAndSetHandleFrom(SourceProcess: THandle; SourceHandle: THandle); virtual;
  public
    constructor CreateFrom(Handle: THandle{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF});
    constructor DuplicateFrom(SourceHandle: THandle); overload;
    constructor DuplicateFrom(SourceObject: TSimpleWinSyncObject); overload;
  {
    When passing handle from 32bit process to 64bit process, it is safe to
    zero- or sign-extend it. In the opposite direction, it is safe to truncate
    it.
  }
    constructor DuplicateFromProcess(SourceProcess: THandle; SourceHandle: THandle);
    constructor DuplicateFromProcessID(SourceProcessID: DWORD; SourceHandle: THandle);
    destructor Destroy; override;
    Function DuplicateForProcess(TargetProcess: THandle): THandle; virtual;
    Function DuplicateForProcessID(TargetProcessID: DWORD): THandle; virtual;
  {
    WARNING - the first overload of method WaitFor intentionaly does not set
              LastError property as the error code is returned in parameter
              ErrCode.
  }
    Function WaitFor(Timeout: DWORD; out ErrCode: DWORD; Alertable: Boolean = False): TWaitResult; overload; virtual;
    Function WaitFor(Timeout: DWORD = INFINITE; Alertable: Boolean = False): TWaitResult; overload; virtual;
    property Handle: THandle read fHandle;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                     TEvent
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TEvent - class declaration
===============================================================================}
type
  TEvent = class(TSimpleWinSyncObject)
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; ManualReset, InitialState: Boolean; const Name: String); overload;
    constructor Create(const Name: String); overload;
    constructor Create; overload;
    constructor Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String); overload;
    constructor Open(const Name: String{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF}); overload;
    Function WaitForAndReset(Timeout: DWORD = INFINITE; Alertable: Boolean = False): TWaitResult;
    Function SetEvent: Boolean;
    Function ResetEvent: Boolean;
  {
    Function PulseEvent is unreliable and should not be used. More info here:
    https://msdn.microsoft.com/en-us/library/windows/desktop/ms684914
  }
    Function PulseEvent: Boolean; deprecated {$IFDEF DeprecatedComment}'Unreliable, do not use.'{$ENDIF};
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                     TMutex
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TMutex - class declaration
===============================================================================}
type
  TMutex = class(TSimpleWinSyncObject)
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; InitialOwner: Boolean; const Name: String); overload;
    constructor Create(const Name: String); overload;
    constructor Create; overload;
    constructor Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String); overload;
    constructor Open(const Name: String{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF}); overload;
    Function WaitForAndRelease(TimeOut: DWORD = INFINITE; Alertable: Boolean = False): TWaitResult;
    Function ReleaseMutex: Boolean;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                   TSemaphore
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSemaphore - class declaration
===============================================================================}
type
  TSemaphore = class(TSimpleWinSyncObject)
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; InitialCount, MaximumCount: Integer; const Name: String); overload;
    constructor Create(InitialCount, MaximumCount: Integer; const Name: String); overload;
    constructor Create(InitialCount, MaximumCount: Integer); overload;
    constructor Open(DesiredAccess: LongWord; InheritHandle: Boolean; const Name: String); overload;
    constructor Open(const Name: String); overload;
    Function WaitForAndRelease(TimeOut: LongWord = INFINITE; Alertable: Boolean = False): TWaitResult;
    Function ReleaseSemaphore(ReleaseCount: Integer; out PreviousCount: Integer): Boolean; overload;
    Function ReleaseSemaphore: Boolean; overload;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                   TWaitableTimer
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TWaitableTimer - class declaration
===============================================================================}
type
  TTimerAPCRoutine = procedure(ArgToCompletionRoutine: Pointer; TimerLowValue, TimerHighValue: DWORD); stdcall;
  PTimerAPCRoutine = ^TTimerAPCRoutine;

  TWaitableTimer = class(TSimpleWinSyncObject)
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; ManualReset: Boolean; const Name: String); overload;
    constructor Create(const Name: String); overload;
    constructor Create; overload;
    constructor Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String); overload;
    constructor Open(const Name: String{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF}); overload;
    Function SetWaitableTimer(DueTime: Int64; Period: Integer; CompletionRoutine: TTimerAPCRoutine; ArgToCompletionRoutine: Pointer; Resume: Boolean): Boolean; overload;
    Function SetWaitableTimer(DueTime: Int64; Period: Integer = 0): Boolean; overload;
    Function SetWaitableTimer(DueTime: TDateTime; Period: Integer; CompletionRoutine: TTimerAPCRoutine; ArgToCompletionRoutine: Pointer; Resume: Boolean): Boolean; overload;
    Function SetWaitableTimer(DueTime: TDateTime; Period: Integer = 0): Boolean; overload;
    Function CancelWaitableTimer: Boolean;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                               Utility functions
--------------------------------------------------------------------------------
===============================================================================}

type
  TMessageWaitOption = (mwoEnable,mwoInputAvailable);

  TMessageWaitOptions = set of TMessageWaitOption;
{
  Waits on multiple handles - the function does not return until wait criteria
  are met, an error occurs or the wait times-out (which of these occured is
  indicated by the result).
  
  Handles of the following windows system objects are allowed:

    Change notification
    Console input
    Event
    Memory resource notification
    Mutex
    Process
    Semaphore
    Thread
    Waitable timer

  Handle array must not be empty and must be shorter or equal to 64, otherwise
  an EWSOMultiWaitInvalidCount exception will be raised.

  If WaitAll is set to true, the function will return wrSignaled only when ALL
  objects are signaled. When set to false, it will return wrSignaled when at
  least one object becomes signaled.

  Timeout is in milliseconds.

  When WaitAll is false, Index indicates which object was signaled or abandoned
  when wrSignaled or wrAbandoned is returned. In case of wrError, the Index
  contains a system error number. For other results, the value of Index is
  undefined.
  When WaitAll is true, value of Index is undefined except for wrError, where
  it again contains system error number.
}
(*
Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult; overload;
Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult; overload;

Function WaitForMultipleHandlesLimited(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleHandlesLimited(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}

{
  Objects array must not be empty, otherwise an EWSOMultiWaitInvalidCount
  exception is raised, but can otherwise contain an arbitrary number of
  objects.

  For other parameters, refer to description of WaitForMultipleHandles.

  Default value for Timeout is INFINITE.
}
Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
*)

{
  WaitResultToStr simply returns textual representation of a given wait result.

  It is meant mainly for debugging purposes.
}
Function WaitResultToStr(WaitResult: TWaitResult): String;

implementation

uses
  Classes, Math,
  AuxTypes, StrRect;

{$IFDEF FPC_DisableWarns}
  {$DEFINE FPCDWM}
  {$DEFINE W5057:={$WARN 5057 OFF}} // Local variable "$1" does not seem to be initialized
  {$DEFINE W5058:={$WARN 5058 OFF}} // Variable "$1" does not seem to be initialized
{$ENDIF}

{===============================================================================
--------------------------------------------------------------------------------
                                TCriticalSection
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TCriticalSection - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TCriticalSection - private methods
-------------------------------------------------------------------------------}

procedure TCriticalSection.SetSpinCountProc(Value: DWORD);
begin
SetSpinCount(Value);
end;

{-------------------------------------------------------------------------------
    TCriticalSection - public methods
-------------------------------------------------------------------------------}

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


{===============================================================================
--------------------------------------------------------------------------------
                                 TWinSyncObject
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TWinSyncObject - class declaration
===============================================================================}
{-------------------------------------------------------------------------------
    TWinSyncObject - protected methods
-------------------------------------------------------------------------------}

Function TWinSyncObject.SetAndRectifyName(const Name: String): Boolean;
begin
fName := Name;
Result := True;
end;

{-------------------------------------------------------------------------------
    TWinSyncObject - public methods
-------------------------------------------------------------------------------}

constructor TWinSyncObject.Create;
begin
inherited Create;
fLastError := 0;
fName := '';
end;

{===============================================================================
--------------------------------------------------------------------------------
                              TSimpleWinSyncObject
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSimpleWinSyncObject - class implentation
===============================================================================}
{-------------------------------------------------------------------------------
    TSimpleWinSyncObject - protected methods
-------------------------------------------------------------------------------}

Function TSimpleWinSyncObject.SetAndRectifyName(const Name: String): Boolean;
begin
inherited SetAndRectifyName(Name);  // only sets the fName field
{
  Names should not contain backslashes (\, #92), but they can separate
  prefixes, so in theory they are allowed - do not replace them, leave this
  responsibility on the user.
}
Result := Length(fName) > 0;
end;

//------------------------------------------------------------------------------

procedure TSimpleWinSyncObject.SetAndCheckHandle(Handle: THandle);
begin
If Handle <> 0 then
  fHandle := Handle
else
  raise EWSOInvalidHandle.CreateFmt('TSimpleWinSyncObject.SetAndCheckHandle: Null handle (0x%.8x).',[GetLastError]);
end;

//------------------------------------------------------------------------------

procedure TSimpleWinSyncObject.DuplicateAndSetHandleFrom(SourceProcess: THandle; SourceHandle: THandle);
var
  NewHandle:  THandle;
begin
If DuplicateHandle(SourceProcess,SourceHandle,GetCurrentProcess,@NewHandle,0,False,DUPLICATE_SAME_ACCESS) then
  SetAndCheckHandle(NewHandle)
else
  raise EWSOHandleDuplicationError.CreateFmt('TSimpleWinSyncObject.DuplicateAndSetHandleFrom: Handle duplication failed (0x%.8x).',[GetLastError]);
end;

{-------------------------------------------------------------------------------
    TSimpleWinSyncObject - public methods
-------------------------------------------------------------------------------}

constructor TSimpleWinSyncObject.CreateFrom(Handle: THandle{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF});
begin
inherited Create;
fHandle := Handle;
If fHandle = 0 then
  raise EWSOInvalidHandle.Create('TSimpleWinSyncObject.CreateFrom: Null handle.');
end;

//------------------------------------------------------------------------------

constructor TSimpleWinSyncObject.DuplicateFrom(SourceHandle: THandle);
begin
DuplicateFromProcess(GetCurrentProcess,SourceHandle);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TSimpleWinSyncObject.DuplicateFrom(SourceObject: TSimpleWinSyncObject);
begin
DuplicateFrom(SourceObject.Handle);
end;

//------------------------------------------------------------------------------

constructor TSimpleWinSyncObject.DuplicateFromProcess(SourceProcess: THandle; SourceHandle: THandle);
begin
inherited Create;
DuplicateAndSetHandleFrom(SourceProcess,SourceHandle);
end;

//------------------------------------------------------------------------------

constructor TSimpleWinSyncObject.DuplicateFromProcessID(SourceProcessID: DWORD; SourceHandle: THandle);
var
  SourceProcess:  THandle;
begin
inherited Create;
SourceProcess := OpenProcess(PROCESS_DUP_HANDLE,False,SourceProcessID);
If SourceProcess <> 0 then
  try
    DuplicateAndSetHandleFrom(SourceProcess,SourceHandle);
  finally
    CloseHandle(SourceProcess);
  end
else raise EWSOHandleDuplicationError.CreateFmt('TSimpleWinSyncObject.DuplicateFromProcessID: Failed to open source process (0x%.8x).',[GetLastError]);
end;

//------------------------------------------------------------------------------

destructor TSimpleWinSyncObject.Destroy;
begin
CloseHandle(fHandle);
inherited;
end;

//------------------------------------------------------------------------------

Function TSimpleWinSyncObject.DuplicateForProcess(TargetProcess: THandle): THandle;
begin
If not DuplicateHandle(GetCurrentProcess,fHandle,TargetProcess,@Result,0,False,DUPLICATE_SAME_ACCESS) then
  raise EWSOHandleDuplicationError.CreateFmt('TSimpleWinSyncObject.DuplicateForProcess: Handle duplication failed (0x%.8x).',[GetLastError]);
end;

//------------------------------------------------------------------------------

Function TSimpleWinSyncObject.DuplicateForProcessID(TargetProcessID: DWORD): THandle;
var
  TargetProcess:  THandle;
begin
TargetProcess := OpenProcess(PROCESS_DUP_HANDLE,False,TargetProcessID);
If TargetProcess <> 0 then
  try
    Result := DuplicateForProcess(TargetProcess);
  finally
    CloseHandle(TargetProcess);
  end
else raise EWSOHandleDuplicationError.CreateFmt('TSimpleWinSyncObject.DuplicateForProcessID: Failed to open target process (0x%.8x).',[GetLastError]);
end;

//------------------------------------------------------------------------------

Function TSimpleWinSyncObject.WaitFor(Timeout: DWORD; out ErrCode: DWORD; Alertable: Boolean = False): TWaitResult;
begin
ErrCode := 0;
case WaitForSingleObjectEx(fHandle,Timeout,Alertable) of
  WAIT_OBJECT_0:      Result := wrSignaled;
  WAIT_ABANDONED:     Result := wrAbandoned;
  WAIT_IO_COMPLETION: Result := wrIOCompletion;
  WAIT_TIMEOUT:       Result := wrTimeout;
  WAIT_FAILED:        begin
                        Result := wrError;
                        ErrCode := GetLastError;
                      end;
else
  Result := wrError;
  ErrCode := GetLastError;
end;
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TSimpleWinSyncObject.WaitFor(Timeout: DWORD = INFINITE; Alertable: Boolean = False): TWaitResult;
begin
Result := WaitFor(Timeout,fLastError,Alertable);
end;


{===============================================================================
--------------------------------------------------------------------------------
                                     TEvent
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TEvent - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TEvent - public methods
-------------------------------------------------------------------------------}

constructor TEvent.Create(SecurityAttributes: PSecurityAttributes; ManualReset, InitialState: Boolean; const Name: String);
begin
inherited Create;
If SetAndRectifyName(Name) then
  SetAndCheckHandle(CreateEventW(SecurityAttributes,ManualReset,InitialState,PWideChar(StrToWide(fName))))
else
  SetAndCheckHandle(CreateEventW(SecurityAttributes,ManualReset,InitialState,nil));
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TEvent.Create(const Name: String);
begin
Create(nil,True,False,Name);
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TEvent.Create;
begin
Create(nil,True,False,'');
end;

//------------------------------------------------------------------------------

constructor TEvent.Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String);
begin
inherited Create;
SetAndRectifyName(Name);
SetAndCheckHandle(OpenEventW(DesiredAccess,InheritHandle,PWideChar(StrToWide(fName))));
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TEvent.Open(const Name: String{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF});
begin
Open(SYNCHRONIZE or EVENT_MODIFY_STATE,False,Name);
end;

//------------------------------------------------------------------------------

Function TEvent.WaitForAndReset(Timeout: DWORD = INFINITE; Alertable: Boolean = False): TWaitResult;
begin
Result := WaitFor(Timeout,Alertable);
If Result = wrSignaled then
  ResetEvent;
end;

//------------------------------------------------------------------------------

Function TEvent.SetEvent: Boolean;
begin
Result := Windows.SetEvent(fHandle);
If not Result then
  fLastError := GetLastError;
end;

//------------------------------------------------------------------------------

Function TEvent.ResetEvent: Boolean;
begin
Result := Windows.ResetEvent(fHandle);
If not Result then
  fLastError := GetLastError;
end;

//------------------------------------------------------------------------------

{$WARN SYMBOL_DEPRECATED OFF}
Function TEvent.PulseEvent: Boolean;
{$WARN SYMBOL_DEPRECATED ON}
begin
Result := Windows.PulseEvent(fHandle);
If not Result then
  fLastError := GetLastError;
end;


{===============================================================================
--------------------------------------------------------------------------------
                                     TMutex
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TMutex - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TMutex - public methods
-------------------------------------------------------------------------------}

constructor TMutex.Create(SecurityAttributes: PSecurityAttributes; InitialOwner: Boolean; const Name: String);
{
  Workaround for known WinAPI bug - CreateMutex only recognizes BOOL(1) as
  true, everything else, including what Delphi/FPC puts there (ie. BOOL(-1)),
  is wrongly seen as false. :/
}
  Function RectBool(Value: Boolean): BOOL;
  begin
    If Value then Result := BOOL(1)
      else Result := BOOL(0);
  end;

begin
inherited Create;
If SetAndRectifyName(Name) then
  SetAndCheckHandle(CreateMutexW(SecurityAttributes,RectBool(InitialOwner),PWideChar(StrToWide(fName))))
else
  SetAndCheckHandle(CreateMutexW(SecurityAttributes,RectBool(InitialOwner),nil));
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TMutex.Create(const Name: String);
begin
Create(nil,False,Name);
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TMutex.Create;
begin
Create(nil,False,'');
end;

//------------------------------------------------------------------------------

constructor TMutex.Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String);
begin
inherited Create;
SetAndRectifyName(Name);
SetAndCheckHandle(OpenMutexW(DesiredAccess,InheritHandle,PWideChar(StrToWide(fName))));
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TMutex.Open(const Name: String{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF});
begin
Open(SYNCHRONIZE or MUTEX_MODIFY_STATE,False,Name);
end;

//------------------------------------------------------------------------------

Function TMutex.WaitForAndRelease(TimeOut: DWORD = INFINITE; Alertable: Boolean = False): TWaitResult;
begin
Result := WaitFor(Timeout,Alertable);
If Result in [wrSignaled,wrAbandoned] then
  ReleaseMutex;
end;

//------------------------------------------------------------------------------

Function TMutex.ReleaseMutex: Boolean;
begin
Result := Windows.ReleaseMutex(fHandle);
If not Result then
  fLastError := GetLastError;
end;


{===============================================================================
--------------------------------------------------------------------------------
                                   TSemaphore
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSemaphore - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TSemaphore - public methods
-------------------------------------------------------------------------------}

constructor TSemaphore.Create(SecurityAttributes: PSecurityAttributes; InitialCount, MaximumCount: Integer; const Name: String);
begin
inherited Create;
If SetAndRectifyName(Name) then
  SetAndCheckHandle(CreateSemaphoreW(SecurityAttributes,InitialCount,MaximumCount,PWideChar(StrToWide(fName))))
else
  SetAndCheckHandle(CreateSemaphoreW(SecurityAttributes,InitialCount,MaximumCount,nil));
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TSemaphore.Create(InitialCount, MaximumCount: Integer; const Name: String);
begin
Create(nil,InitialCount,MaximumCount,Name);
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TSemaphore.Create(InitialCount, MaximumCount: Integer);
begin
Create(nil,InitialCount,MaximumCount,'');
end;

//------------------------------------------------------------------------------

constructor TSemaphore.Open(DesiredAccess: LongWord; InheritHandle: Boolean; const Name: String);
begin
inherited Create;
SetAndRectifyName(Name);
SetAndCheckHandle(OpenSemaphoreW(DesiredAccess,InheritHandle,PWideChar(StrToWide(fName))));
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TSemaphore.Open(const Name: String);
begin
Open(SYNCHRONIZE or SEMAPHORE_MODIFY_STATE,False,Name);
end;
 
//------------------------------------------------------------------------------

Function TSemaphore.WaitForAndRelease(TimeOut: LongWord = INFINITE; Alertable: Boolean = False): TWaitResult;
begin
Result := WaitFor(Timeout,Alertable);
If Result in [wrSignaled,wrAbandoned] then
  ReleaseSemaphore;
end;

//------------------------------------------------------------------------------

Function TSemaphore.ReleaseSemaphore(ReleaseCount: Integer; out PreviousCount: Integer): Boolean;
begin
Result := Windows.ReleaseSemaphore(fHandle,ReleaseCount,@PreviousCount);
If not Result then
  fLastError := GetLastError;
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

Function TSemaphore.ReleaseSemaphore: Boolean;
var
  Dummy:  Integer;
begin
Result := ReleaseSemaphore(1,Dummy);
end;


{===============================================================================
--------------------------------------------------------------------------------
                                   TWaitableTimer
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TWaitableTimer - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TWaitableTimer - public methods
-------------------------------------------------------------------------------}

constructor TWaitableTimer.Create(SecurityAttributes: PSecurityAttributes; ManualReset: Boolean; const Name: String);
begin
inherited Create;
If SetAndRectifyName(Name) then
  SetAndCheckHandle(CreateWaitableTimerW(SecurityAttributes,ManualReset,PWideChar(StrToWide(fName))))
else
  SetAndCheckHandle(CreateWaitableTimerW(SecurityAttributes,ManualReset,nil));
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TWaitableTimer.Create(const Name: String);
begin
Create(nil,True,Name);
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TWaitableTimer.Create;
begin
Create(nil,True,'');
end;

//------------------------------------------------------------------------------

constructor TWaitableTimer.Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String);
begin
inherited Create;
SetAndRectifyName(Name);
SetAndCheckHandle(OpenWaitableTimerW(DesiredAccess,InheritHandle,PWideChar(StrToWide(fName))));
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

constructor TWaitableTimer.Open(const Name: String{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF});
begin
Open(SYNCHRONIZE or TIMER_MODIFY_STATE,False,Name);
end;

//------------------------------------------------------------------------------

{$IFDEF FPCDWM}{$PUSH}W5058{$ENDIF}
Function TWaitableTimer.SetWaitableTimer(DueTime: Int64; Period: Integer; CompletionRoutine: TTimerAPCRoutine; ArgToCompletionRoutine: Pointer; Resume: Boolean): Boolean;
begin
Result := Windows.SetWaitableTimer(fHandle,DueTime,Period,@CompletionRoutine,ArgToCompletionRoutine,Resume);
If not Result then
  fLastError := GetLastError;
end;
{$IFDEF FPCDWM}{$POP}{$ENDIF}

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

Function TWaitableTimer.SetWaitableTimer(DueTime: Int64; Period: Integer = 0): Boolean;
begin
Result := SetWaitableTimer(DueTime,Period,nil,nil,False);
end;

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

{$IFDEF FPCDWM}{$PUSH}W5057{$ENDIF}
Function TWaitableTimer.SetWaitableTimer(DueTime: TDateTime; Period: Integer; CompletionRoutine: TTimerAPCRoutine; ArgToCompletionRoutine: Pointer; Resume: Boolean): Boolean;

  Function DateTimeToFileTime(DateTime: TDateTime): TFileTime;
  var
    LocalTime:  TFileTime;
    SystemTime: TSystemTime;
  begin
    Result.dwLowDateTime := 0;
    Result.dwHighDateTime := 0;
    DateTimeToSystemTime(DateTime,SystemTime);
    If SystemTimeToFileTime(SystemTime,LocalTime) then
      begin
        If not LocalFileTimeToFileTime(LocalTime,Result) then
          raise EWSOTimeConversionError.CreateFmt('TWaitableTimer.SetWaitableTimer.DateTimeToFileTime: ' +
            'LocalFileTimeToFileTime failed with error 0x%.8x.',[GetLastError]);
      end
    else raise EWSOTimeConversionError.CreateFmt('TWaitableTimer.SetWaitableTimer.DateTimeToFileTime: ' +
           'SystemTimeToFileTime failed with error 0x%.8x.',[GetLastError]);
  end;

begin
Result := SetWaitableTimer(Int64(DateTimeToFileTime(DueTime)),Period,CompletionRoutine,ArgToCompletionRoutine,Resume);
If not Result then
  fLastError := GetLastError;
end;
{$IFDEF FPCDWM}{$POP}{$ENDIF}

//   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---   ---

Function TWaitableTimer.SetWaitableTimer(DueTime: TDateTime; Period: Integer = 0): Boolean;
begin
Result := SetWaitableTimer(DueTime,Period,nil,nil,False);
end;

//------------------------------------------------------------------------------

Function TWaitableTimer.CancelWaitableTimer: Boolean;
begin
Result := Windows.CancelWaitableTimer(fHandle);
If not Result then
  fLastError := GetLastError;
end;

{===============================================================================
--------------------------------------------------------------------------------
                               Utility functions
--------------------------------------------------------------------------------
===============================================================================}

{$IF not Declared(MWMO_INPUTAVAILABLE)}
const
  MWMO_INPUTAVAILABLE = DWORD($00000004);
{$IFEND}

const
  MAXIMUM_WAIT_OBJECTS = 3; {$message 'debug'}
(*
{===============================================================================
    Utility functions - waiter thread declaration
===============================================================================}
type
  TWaiterThread = class(TThread)
  protected
    fFreeMark:    Integer;
    fHandles:     array of THandle;
    fWaitAll:     Boolean;
    fTimeout:     DWORD;
    fIndexOffset: Integer;
    fIndex:       Integer;
    fResult:      TWaitResult;
    procedure Execute; override;
  public
    constructor Create(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; IndexOffset: Integer);
    Function MarkForAutoFree: Boolean; virtual;
    property IndexOffset: Integer read fIndexOffset;
    property Index: Integer read fIndex;
    property Result: TWaitResult read fResult;
  end;

{===============================================================================
    Utility functions - waiter thread implementation
===============================================================================}

Function WaitForMultipleHandles_Thread(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer): TWaitResult; forward;

{-------------------------------------------------------------------------------
    Utility functions - waiter thread protected methods
-------------------------------------------------------------------------------}

procedure TWaiterThread.Execute;
begin
fResult := WaitForMultipleHandles_Thread(Addr(fHandles[Low(fHandles)]),Length(fHandles),fWaitAll,fTimeout,fIndex);
If InterlockedExchange(fFreeMark,-1) <> 0 then
  FreeOnTerminate := True;
end;

{-------------------------------------------------------------------------------
    Utility functions - waiter thread public methods
-------------------------------------------------------------------------------}

constructor TWaiterThread.Create(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; IndexOffset: Integer);
var
  i:  Integer;
begin
inherited Create(False);
FreeOnTerminate := False;
fFreeMark := 0;
SetLength(fHandles,Length(Handles));
For i := Low(Handles) to High(Handles) do
  fHandles[i] := Handles[i];
fWaitAll := WaitAll;
fTimeout := Timeout;
fIndexOffset := IndexOffset;
fIndex := -1;
fResult := wrError;
end;

//------------------------------------------------------------------------------

Function TWaiterThread.MarkForAutoFree: Boolean;
begin
Result := InterlockedExchange(fFreeMark,-1) = 0;
end;

{===============================================================================
    Utility functions - internal functions
===============================================================================}

Function MaxWaitObjCount(MsgWaitOptions: TMessageWaitOptions): Integer;
begin
If mwoEnable in MsgWaitOptions then
  Result := MAXIMUM_WAIT_OBJECTS - 1
else
  Result := MAXIMUM_WAIT_OBJECTS;
end;

//------------------------------------------------------------------------------

Function WaitForMultipleHandles_Sys(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
var
  WaitResult: DWORD;
  MsgFlags:   DWORD;
begin
If (Count > 0) and (Count <= MaxWaitObjCount(MsgWaitOptions)) then
  begin
    Index := -1;
    If mwoEnable in MsgWaitOptions then
      begin
        // waiting with messages, construct flags
        MsgFlags := 0;
        If WaitAll then
          MsgFlags := MsgFlags or MWMO_WAITALL;
        If Alertable then
          MsgFlags := MsgFlags or MWMO_ALERTABLE;
        If mwoInputAvailable in MsgWaitOptions then
          MsgFlags := MsgFlags or MWMO_INPUTAVAILABLE;
        WaitResult := MsgWaitForMultipleObjectsEx(DWORD(Count),{$IFDEF FPC}LPHANDLE{$ELSE}PWOHandleArray{$ENDIF}(Handles),Timeout,WakeMask,MsgFlags);
      end
    // "normal" waiting
    else WaitResult := WaitForMultipleObjectsEx(DWORD(Count),{$IFDEF FPC}LPHANDLE{$ELSE}PWOHandleArray{$ENDIF}(Handles),WaitAll,Timeout,Alertable);
    // process result
    case WaitResult of
      WAIT_OBJECT_0..
      Pred(WAIT_OBJECT_0 + MAXIMUM_WAIT_OBJECTS):
        If not(mwoEnable in MsgWaitOptions) or (Integer(WaitResult - WAIT_OBJECT_0) < Count) then
          begin
            Result := wrSignaled;
            If not WaitAll then
              Index := Integer(WaitResult - WAIT_OBJECT_0);
          end
        else Result := wrMessage;
      WAIT_ABANDONED_0..
      Pred(WAIT_ABANDONED_0 + MAXIMUM_WAIT_OBJECTS):
        begin
          Result := wrAbandoned;
          If not WaitAll then
            Index := Integer(WaitResult - WAIT_ABANDONED_0);
        end;
      WAIT_IO_COMPLETION:
        Result := wrIOCompletion;
      WAIT_TIMEOUT:
        Result := wrTimeout;
      WAIT_FAILED:
        Result := wrError;
    else
      Result := wrError;
    end;
    If Result = wrError then
      Index := Integer(GetLastError);
  end
else raise EWSOMultiWaitInvalidCount.CreateFmt('WaitForMultipleHandles_Sys: Invalid handle count (%d).',[Count]);
end;

//------------------------------------------------------------------------------

Function WaitForMultipleHandles_HighAll(Handles: PHandle; Count: Integer; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
var
  WaiterThreads:  array of TWaiterThread;
  WaitHandles:    array of THandle;
  i,j,Cntr:       Integer;
  HandleTemp:     array of THandle;
begin
{
  There is more than MaxWaitObjCount handles to be waited on and we will be
  waiting until all of them are signaled.

  We spawn appropriate number of waiter threads and split the handles between
  them. Each thread will then wait on a portion of handles and we will wait on
  the waiter threads.

  When handles will become signaled or their waiting ends in other ways (error,
  timeout, ...), the waiter threads will end their waiting and become in turn
  signaled too, at which point this function finishes and exists.
}
{
  Prepare waiter threads and will them with handles to wait on.

  Note that the waiter threads can get full MAXIMUM_WAIT_OBJECTS since none of
  them will wait on messages or any other specialities.
}
// prepare array of waiter threads / wait handles
SetLength(WaiterThreads,Min(Ceil(Count / MAXIMUM_WAIT_OBJECTS),MaxWaitObjCount(MsgWaitOptions)));
SetLength(WaitHandles,Length(WaiterThreads));
// create and fill waiter threads
Cntr := 0;
For i := Low(WaiterThreads) to High(WaiterThreads) do
  begin
    If i < High(WaiterThreads) then
      SetLength(HandleTemp,Min(Ceil(Count / Length(WaiterThreads)),MAXIMUM_WAIT_OBJECTS))
    else
      SetLength(HandleTemp,Count - Cntr);
    For j := Low(HandleTemp) to High(HandleTemp) do
      begin
        HandleTemp[j] := PHandle(PtrUInt(Handles) + PtrUInt(Cntr * SizeOf(THandle)))^;
        Inc(Cntr);
      end; 
    {
      Threads enter their internal waiting immediately.

      Any waiter thread can finish even before its handle is obtained, but
      the handle should still be walid and usable in waiting since no thread
      is freed automatically.
    }
    WaiterThreads[i] := TWaiterThread.Create(HandleTemp,True,Timeout,-1);
    WaitHandles[i] := WaiterThreads[i].Handle;
  end;
{
  Now wait on all waiter threads with no timeout - the timeout is in effect
  for objects we are waiting on, which the waiter threads are not.

  Result of the entire function is set to the result of this waiting.
}
Result := WaitForMultipleHandles_Sys(Addr(WaitHandles[Low(WaitHandles)]),Length(WaitHandles),True,INFINITE,Index,Alertable,MsgWaitOptions,WakeMask);
Index := -1;  // index from wait function is of no use here
{
  We have to process result from waiting on the waiter threads.

  For wrSignaled and wrAbandoned, we traverse all threads and check their
  results, as it is possible that some (or even all) of them ended with
  result being other than wrSignaled or wrAbandoned.
  If we encounter "worse" result than is set by waiting on the waiting threads,
  then such result will become a new result of this function.
  If wrError is encountered in any thread, then the traversing will end at that
  point, result of this function will be set to wrError and Index will be set
  to Index of that particular waiter thread (which should contain error code).

  wrIOCompletion and wrMessage are taken as they are and nothing is done about
  then. Note that these results should only be possible in thread that initiated
  the waiting, as all waiter threads are in non-alertable non-message waiting.

  wrTimeout should not happen, so we are treating it as a critical error.

  wrError indicates something bad has happened, and since the error originates
  from waiting on waiter threads and not on the original objects, it is again
  treated as critical error, not as an error to be reported along with error
  code.
}
case Result of
  wrSignaled,
  wrAbandoned:    begin
                    // Check whether all waiter threads ended with result
                    // being signaled or abandoned.
                    For i := Low(WaiterThreads) to High(WaiterThreads) do
                      If WaiterThreads[i].Result > Result then
                        begin
                          Result := WaiterThreads[i].Result;
                          If Result = wrError then
                            begin
                              Index := WaiterThreads[i].Index; 
                              Break{For i};
                            end;
                        end;
                  end;
  wrIOCompletion: Index := -1;  // do nothing, only possible in an alertable waiting in the initiating thread
  wrMessage:      Index := -1;  // do nothing, only possible in a message waiting in the initiating thread
  wrTimeout:      raise EWSOWaitError.Create('WaitForMultipleHandles_HighAll: Wait timeout not allowed here.');
  wrError:        raise EWSOWaitError.CreateFmt('WaitForMultipleHandles_HighAll: Wait error (%d).',[GetLastError]);
else
 {some nonsensical result, should not happen}
  raise EWSOWaitError.CreateFmt('WaitForMultipleHandles_HighAll: Invalid wait result (%d).',[Ord(Result)]);
end;
{
  Some waiter threads might be still waiting. We do not need them anymore and
  forcefull termination is not a good idea at this point, so we mark them for
  automatic freeing at their termination and leave them to their fate (all
  waiter threads, if still present, will be terminated at the program exit).

  If any thread already finished its waiting (in which case its method
  MarkForAutoFree returns false), then it is freed immediately.
}
For i := Low(WaiterThreads) to High(WaiterThreads) do
  If not WaiterThreads[i].MarkForAutoFree then
    begin
      WaiterThreads[i].WaitFor;
      WaiterThreads[i].Free;
    end;
end;

//------------------------------------------------------------------------------

Function WaitForMultipleHandles_HighOne(Handles: PHandle; Count: Integer; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
var
  Releaser:       TEvent;
  WaiterThreads:  array of TWaiterThread;
  WaitHandles:    array of THandle;
  i,j,Cntr:       Integer;
  HandleTemp:     array of THandle;
begin
{
  There is more than MaxWaitObjCount handles to be waited and if any single one
  of them gets signaled, the waiting will end.

  First handle is expected to be a releaser event.

  We spawn appropriate number of waiter threads and split the handles between
  them. Each thread will, along with its portion of handles, get a handle to
  releaser.

  When one of the handles get signaled and waiting in this function ends, the
  releaser is set to signaled. And since every thread has it among its wait
  handles, they all end their waiting and exit.
}
Releaser := TEvent.DuplicateFrom(Handles^);
{
  Create and fill waiter threads, each thread gets a releaser as its first
  handle.
}
SetLength(WaiterThreads,Min(Ceil(Pred(Count) / Pred(MAXIMUM_WAIT_OBJECTS)),MaxWaitObjCount(MsgWaitOptions)));
SetLength(WaitHandles,Length(WaiterThreads));
Cntr := 1;  // first handle (the releaser) is skipped
For i := Low(WaiterThreads) to High(WaiterThreads) do
  begin
    If i < High(WaiterThreads) then
      SetLength(HandleTemp,Min(Succ(Ceil(Pred(Count) / Length(WaiterThreads))),MAXIMUM_WAIT_OBJECTS))
    else
      SetLength(HandleTemp,Succ(Count - Cntr));
    HandleTemp[Low(HandleTemp)] := Releaser.Handle;
    For j := Succ(Low(HandleTemp)) to High(HandleTemp) do
      begin
        HandleTemp[j] := PHandle(PtrUInt(Handles) + PtrUInt(Cntr * SizeOf(THandle)))^;
        Inc(Cntr);
      end;
    //  Threads enter their internal waiting immediately.
    WaiterThreads[i] := TWaiterThread.Create(HandleTemp,False,Timeout,Cntr - Length(HandleTemp));
    WaitHandles[i] := WaiterThreads[i].Handle;
  end;
// wait on threads, no timeout
Result := WaitForMultipleHandles_Sys(Addr(WaitHandles[Low(WaitHandles)]),Length(WaitHandles),False,INFINITE,Index,Alertable,MsgWaitOptions,WakeMask);
{
  Release all threads and wait until they all exit.
}
Releaser.SetEvent;
For i := Low(WaiterThreads) to High(WaiterThreads) do
  WaiterThreads[i].WaitFor;
{
  Result processing.

  Most results have the same meaning and effect as in wainting on all handles,
  but wrSignaled and wrAbandoned must be processed to obtain true index of the
  signaling handle it has in an array passed to this function.
}
case Result of
  wrSignaled,
  wrAbandoned:    begin
                    {$message 'rework - store "first" result via interlocked funcs into passed p-variable'}
                    {
                      warning - more than one object can be acquired, if an object
                      is acquired and it is not the first one, it must be released 
                    }
                    If (Index >= Low(WaiterThreads)) and (Index <= High(WaiterThreads)) then
                      begin
                        Index := -1;
                        For i := Low(WaiterThreads) to High(WaiterThreads) do
                          If (WaiterThreads[i].Result in [wrSignaled,wrAbandoned]) and (WaiterThreads[i].Index > 0) then
                            Index := WaiterThreads[i].IndexOffset + WaiterThreads[i].Index;
                      end
                    else raise EWSOWaitError.CreateFmt('WaitForMultipleHandles_HighOne: Invalid index %d.',[Index]);
                  end;
  wrIOCompletion: Index := -1;  // do nothing, only possible in an alertable waiting in the initiating thread
  wrMessage:      Index := -1;  // do nothing, only possible in a message waiting in the initiating thread
  wrTimeout:      raise EWSOWaitError.Create('WaitForMultipleHandles_HighOne: Wait timeout not allowed here.');
  wrError:        raise EWSOWaitError.CreateFmt('WaitForMultipleHandles_HighOne: Wait error (%d).',[GetLastError]);
else
 {some nonsensical result, should not happen}
  raise EWSOWaitError.CreateFmt('WaitForMultipleHandles_HighOne: Invalid wait result (%d).',[Ord(Result)]);
end;
// all waiter threads are now finished, so just free them
For i := Low(WaiterThreads) to High(WaiterThreads) do
  WaiterThreads[i].Free;
{
  Free releaser. Note that it has duplicated handle, so freeing it will not
  destroy the original object.
}
Releaser.Free;
end;

//------------------------------------------------------------------------------

Function WaitForMultipleHandles_Thread(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer): TWaitResult;
begin
{
  This function is only called from waiter threads, so no alertable or message
  waiting is allowed here.
}
If Count > MAXIMUM_WAIT_OBJECTS then
  begin
    If WaitAll then
      Result := WaitForMultipleHandles_HighAll(Handles,Count,Timeout,Index,False,[],0)
    else
      Result := WaitForMultipleHandles_HighOne(Handles,Count,Timeout,Index,False,[],0);
  end
else Result := WaitForMultipleHandles_Sys(Handles,Count,WaitAll,Timeout,Index,False,[],0);
end;

//------------------------------------------------------------------------------

Function WaitForMultipleHandles_Internal(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
var
  Releaser: TEvent;
  HndTemp:  array of THandle;
  i:        Integer;
begin
Index := -1;
If Count > 0 then
  begin
    If Count > MaxWaitObjCount(MsgWaitOptions) then
      begin
        If not WaitAll then
          begin
            Releaser := TEvent.Create(nil,True,False,''); // manual reset, nonsignaled
            try
              SetLength(HndTemp,Count + 1);
              For i := 0 to Pred(Count) do 
                HndTemp[i + 1] := PHandle(PtrUInt(Handles) + PtrUInt(i * SizeOf(THandle)))^;
              // pass releaser handle
              HndTemp[0] := Releaser.Handle;
              Result := WaitForMultipleHandles_HighOne(Addr(HndTemp[Low(HndTemp)]),Length(HndTemp),Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
              Releaser.SetEvent;
              If Result in [wrSignaled,wrAbandoned] then
                Dec(Index);
            finally
              Releaser.Free;
            end;
          end
        else Result := WaitForMultipleHandles_HighAll(Handles,Count,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
      end
    else Result := WaitForMultipleHandles_Sys(Handles,Count,WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
  end
else raise EWSOMultiWaitInvalidCount.CreateFmt('WaitForMultipleHandles_Internal: Invalid handle count (%d).',[Count]);
end;

//------------------------------------------------------------------------------

Function WaitForMultipleObjects_Internal(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
var
  Releaser: TEvent;
  HndTemp:  array of THandle;
  i:        Integer;
begin
Index := -1;
If Length(Objects) > 0 then
  begin
    If (Length(Objects) > MaxWaitObjCount(MsgWaitOptions)) and not WaitAll then
      begin
        Releaser := TEvent.Create(nil,True,False,'');
        try
          SetLength(HndTemp,Length(Objects) + 1);
          For i := Low(Objects) to High(Objects) do
            HndTemp[i + 1] := Objects[i].Handle;
          HndTemp[0] := Releaser.Handle;
          Result := WaitForMultipleHandles_HighOne(Addr(HndTemp[Low(HndTemp)]),Length(HndTemp),Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
          Releaser.SetEvent;
          If Result in [wrSignaled,wrAbandoned] then
            Dec(Index);
        finally
          Releaser.Free;
        end;
      end
    else
      begin
        // prepare handle array
        SetLength(HndTemp,Length(Objects));
        For i := Low(Objects) to High(Objects) do
          HndTemp[i] := Objects[i].Handle;
        // wait on handles
        If Length(HndTemp) > MaxWaitObjCount(MsgWaitOptions) then
          Result := WaitForMultipleHandles_HighAll(Addr(HndTemp[Low(HndTemp)]),Length(HndTemp),Timeout,Index,Alertable,MsgWaitOptions,WakeMask)
        else
          Result := WaitForMultipleHandles_Sys(Addr(HndTemp[Low(HndTemp)]),Length(HndTemp),WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
      end;
  end
else raise EWSOMultiWaitInvalidCount.CreateFmt('WaitForMultipleObjects_Internal: Invalid object count (%d).',[Length(Objects)]);
end;

{===============================================================================
    Utility functions - public functions
===============================================================================}

Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
begin
Result := WaitForMultipleHandles_Internal(Handles,Count,WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask)
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult;
begin
Result := WaitForMultipleHandles_Internal(Handles,Count,WaitAll,Timeout,Index,Alertable,[],0)
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
begin
If Length(Handles) > 0 then
  Result := WaitForMultipleHandles_Internal(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask)
else
  raise EWSOMultiWaitInvalidCount.CreateFmt('WaitForMultipleHandles: Invalid handle count (%d).',[Length(Handles)]);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult;
begin
If Length(Handles) > 0 then
  Result := WaitForMultipleHandles_Internal(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,Timeout,Index,Alertable,[],0)
else
  raise EWSOMultiWaitInvalidCount.CreateFmt('WaitForMultipleHandles: Invalid handle count (%d).',[Length(Handles)]);
end;

//------------------------------------------------------------------------------

Function WaitForMultipleHandlesLimited(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
begin
Result := WaitForMultipleHandles_Sys(Handles,Count,WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandlesLimited(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult;
begin
Result := WaitForMultipleHandles_Sys(Handles,Count,WaitAll,Timeout,Index,Alertable,[],0);
end;

//------------------------------------------------------------------------------

Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
begin
Result := WaitForMultipleObjects_Internal(Objects,WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult;
begin
Result := WaitForMultipleObjects_Internal(Objects,WaitAll,Timeout,Index,Alertable,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForMultipleObjects_Internal(Objects,WaitAll,Timeout,Index,Alertable,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForMultipleObjects_Internal(Objects,WaitAll,Timeout,Index,False,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForMultipleObjects_Internal(Objects,WaitAll,INFINITE,Index,False,[],0);
end;

//------------------------------------------------------------------------------
*)
Function WaitResultToStr(WaitResult: TWaitResult): String;
const
  WR_STRS: array[TWaitResult] of String = ('Signaled','Abandoned','IOCompletion','Message','Timeout','Error');
begin
If (WaitResult >= Low(TWaitResult)) and (WaitResult <= High(TWaitResult)) then
  Result := WR_STRS[WaitResult]
else
  Result := '<invalid>';
end;


{===============================================================================
--------------------------------------------------------------------------------
                               Unit initialization
--------------------------------------------------------------------------------
===============================================================================}

procedure Initialize;
var
  TestArray:  array of THandle;
begin
{
  Check whether array of handles does or does not have some gaps (due to
  alignment) between items - current implementation assumes it doesn't.
}
SetLength(TestArray,2);
If (PtrUInt(Addr(TestArray[Succ(Low(TestArray))])) - PtrUInt(Addr(TestArray[Low(TestArray)]))) <> SizeOf(THandle) then
  raise EWSOException.Create('Initialize: Unsupported implementation detail (array items alignment).');
end;

//------------------------------------------------------------------------------

initialization
  Initialize;

end.

