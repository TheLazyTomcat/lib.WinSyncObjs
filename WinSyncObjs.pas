{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  WinSyncObjs

    Set of classes encapsulating windows synchronization objects.

  Version 1.0.5 (2020-06-07)

  Last change 2020-08-02

  ©2016-2020 František Milt

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
  {$DEFINE FPC_DisableWarns}
  {$MACRO ON}
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
  TWaitResult = (wrSignaled, wrAbandoned, wrIOCompletion, wrTimeout, wrError);

  // library-specific exceptions
  EWSOException = class(Exception);

  EWSOTimeConversionError   = class(EWSOException);
  EWSOMultiWaitInvalidCount = class(EWSOException);
  EWSOWaitError             = class(EWSOException);

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
  private
    fHandle:      THandle;
    fLastError:   Integer;
    fName:        String;
  protected
    Function SetAndRectifyName(const Name: String): Boolean; virtual;
    procedure SetAndCheckHandle(Handle: THandle); virtual;
  public
    destructor Destroy; override;
    Function WaitFor(Timeout: DWORD = INFINITE; Alertable: Boolean = False): TWaitResult; virtual;
    property Handle: THandle read fHandle;
    property LastError: Integer read fLastError;
    property Name: String read fName;
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
  TEvent = class(TWinSyncObject)
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
  TMutex = class(TWinSyncObject)
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
  TSemaphore = class(TWinSyncObject)
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

  TWaitableTimer = class(TWinSyncObject)
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
{
  Objects array must not be empty and must not contain more than 64 objects,
  otherwise an EWSOMultiWaitInvalidCount exception is raised.

  If WaitAll is set to true, the function will return wrSignaled only when ALL
  objects are signaled, otherwise it will return wrSignaled when at least one
  object becomes signaled.

  Timeout is in milliseconds.

  Index indicates which object was signaled or abandoned when wrSignaled or
  wrAbandoned is returned. In case of wrError, the Index contains a system
  error number. For other results, the value of Index is undefined.

  Default value for WaitAll is false.
  Default value for Timeout is INFINITE.
}
Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult; overload;
Function WaitForMultipleObjects(Objects: array of TWinSyncObject; Timeout: DWORD; out Index: Integer): TWaitResult; overload;
Function WaitForMultipleObjects(Objects: array of TWinSyncObject; Timeout: DWORD): TWaitResult; overload;
Function WaitForMultipleObjects(Objects: array of TWinSyncObject): TWaitResult; overload;

Function WaitResultToStr(WaitResult: TWaitResult): String;

implementation

uses
  Classes, Math,
  StrRect;

{$IFDEF FPC_DisableWarns}
  {$DEFINE FPCDWM}
  {$DEFINE W5057:={$WARN 5057 OFF}} // Local variable "$1" does not seem to be initialized
  {$DEFINE W5058:={$WARN 5058 OFF}} // Variable "$1" does not seem to be initialized
{$ENDIF}

const
  MAXIMUM_WAIT_OBJECTS = 4;{$message 'debug'}

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
    TWinSyncObject - class implentation
===============================================================================}
{-------------------------------------------------------------------------------
    TWinSyncObject - protected methods
-------------------------------------------------------------------------------}

Function TWinSyncObject.SetAndRectifyName(const Name: String): Boolean;
begin
fName := Name;
If Length(fName) > MAX_PATH then
  SetLength(fName,MAX_PATH);
Result := Length(fName) > 0;
end;

//------------------------------------------------------------------------------

procedure TWinSyncObject.SetAndCheckHandle(Handle: THandle);
begin
fHandle := Handle;
If fHandle = 0 then
  begin
    fLastError := GetLastError;
    RaiseLastOSError;
  end;
end;

{-------------------------------------------------------------------------------
    TWinSyncObject - public methods
-------------------------------------------------------------------------------}

destructor TWinSyncObject.Destroy;
begin
CloseHandle(fHandle);
inherited;
end;

//------------------------------------------------------------------------------

Function TWinSyncObject.WaitFor(Timeout: DWORD = INFINITE; Alertable: Boolean = False): TWaitResult;
begin
case WaitForSingleObjectEx(fHandle,Timeout,Alertable) of
  WAIT_OBJECT_0:      Result := wrSignaled;
  WAIT_ABANDONED:     Result := wrAbandoned;
  WAIT_IO_COMPLETION: Result := wrIOCompletion;
  WAIT_TIMEOUT:       Result := wrTimeout;
  WAIT_FAILED:        begin
                        Result := wrError;
                        fLastError := GetLastError;
                      end;
else
  Result := wrError;
  fLastError := GetLastError;
end;
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
  SetAndCheckHandle(CreateEvent(SecurityAttributes,ManualReset,InitialState,PChar(StrToWin(fName))))
else
  SetAndCheckHandle(CreateEvent(SecurityAttributes,ManualReset,InitialState,nil));
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
SetAndCheckHandle(OpenEvent(DesiredAccess,InheritHandle,PChar(StrToWin(fName))));
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
begin
inherited Create;
If SetAndRectifyName(Name) then
  SetAndCheckHandle(CreateMutex(SecurityAttributes,InitialOwner,PChar(StrToWin(fName))))
else
  SetAndCheckHandle(CreateMutex(SecurityAttributes,InitialOwner,nil));
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
SetAndCheckHandle(OpenMutex(DesiredAccess,InheritHandle,PChar(StrToWin(fName))));
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
  SetAndCheckHandle(CreateSemaphore(SecurityAttributes,InitialCount,MaximumCount,PChar(StrToWin(fName))))
else
  SetAndCheckHandle(CreateSemaphore(SecurityAttributes,InitialCount,MaximumCount,nil));
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
SetAndCheckHandle(OpenSemaphore(DesiredAccess,InheritHandle,PChar(StrToWin(fName))));
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
  SetAndCheckHandle(CreateWaitableTimer(SecurityAttributes,ManualReset,PChar(StrToWin(fName))))
else
  SetAndCheckHandle(CreateWaitableTimer(SecurityAttributes,ManualReset,nil));
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
SetAndCheckHandle(OpenWaitableTimer(DesiredAccess,InheritHandle,PChar(StrToWin(fName))));
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

  Function DateTimeToFileTime(DateTime: TDateTime): FileTime;
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
          raise EWSOTimeConversionError.CreateFmt('LocalFileTimeToFileTime failed with error 0x%.8x.',[GetLastError]);
      end
    else raise EWSOTimeConversionError.CreateFmt('SystemTimeToFileTime failed with error 0x%.8x.',[GetLastError]);
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
{===============================================================================
    Utility functions - waiter thread declaration
===============================================================================}
type
  TWaiterThread = class(TThread)
  protected
    fObjects:   array of TWinSyncObject;
    fWaitAll:   Boolean;
    fTimeout:   DWORD;
    fAlertable: Boolean;
    fIndexBase: Integer;
    fIndex:     Integer;
    fResult:    TWaitResult;
    procedure Execute; override;
  public
    constructor Create(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean; IndexBase: Integer);
    property IndexBase: Integer read fIndexBase;
    property Index: Integer read fIndex;
    property Result: TWaitResult read fResult;
  end;

{===============================================================================
    Utility functions - waiter thread implementation
===============================================================================}

Function WaitForMultipleObjects_Internal(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult; forward;

{-------------------------------------------------------------------------------
    Utility functions - waiter thread protected methods
-------------------------------------------------------------------------------}

procedure TWaiterThread.Execute;
begin
(*
if LEngth(fObjects) < MAXIMUM_WAIT_OBJECTS then
  begin
    fresult := wrError;
    findex := -666;
  end
else
*){$message 'debug'}
fResult := WaitForMultipleObjects_Internal(fObjects,fWaitAll,fTimeout,fIndex,fAlertable);
end;

{-------------------------------------------------------------------------------
    Utility functions - waiter thread public methods
-------------------------------------------------------------------------------}

constructor TWaiterThread.Create(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean; IndexBase: Integer);
var
  i:  Integer;
begin
inherited Create(False);
FreeOnTerminate := False;
SetLength(fObjects,Length(Objects));
For i := Low(Objects) to High(Objects) do
  fObjects[i] := Objects[i];   
fWaitAll := WaitAll;
fTimeout := Timeout;
fAlertable := Alertable;
fIndexBase := IndexBase;
fIndex := -1;
fResult := wrError;
end;

{===============================================================================
    Utility functions - internal functions
===============================================================================}

Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult;
var
  WaitResult: DWORD;
begin
Index := -1;
// waiting
WaitResult := WaitForMultipleObjectsEx(Length(Handles),Addr(Handles[Low(Handles)]),WaitAll,Timeout,Alertable);
// process result
case WaitResult of
  WAIT_OBJECT_0..
  Pred(WAIT_OBJECT_0 + MAXIMUM_WAIT_OBJECTS):
    begin
      Result := wrSignaled;
      Index := Integer(WaitResult - WAIT_OBJECT_0);
    end;
  WAIT_ABANDONED_0..
  Pred(WAIT_ABANDONED_0 + MAXIMUM_WAIT_OBJECTS):
    begin
      Result := wrAbandoned;
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
end;

//------------------------------------------------------------------------------

Function WaitForMultipleObjects_Low(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult;
var
  Handles:  packed array of THandle;
  i:        Integer;
begin
Index := -1;
// prepare handle array
SetLength(Handles,Length(Objects));
For i := Low(Objects) to High(Objects) do
  Handles[i] := Objects[i].Handle;
Result := WaitForMultipleHandles(Handles,WaitAll,Timeout,Index,Alertable);
end;

//------------------------------------------------------------------------------

Function WaitForMultipleObjects_High(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult;
var
  WaiterThreads:  array of TWaiterThread;
  WaiterHandles:  packed array of THandle;
  i,j:            Integer;
  ObjectsTemp:    array of TWinSyncObject;
begin
If WaitAll then
  begin
    // prepare array of waiter threads
    SetLength(WaiterThreads,Min(Ceil(Length(Objects) / MAXIMUM_WAIT_OBJECTS),MAXIMUM_WAIT_OBJECTS));
    SetLength(WaiterHandles,Length(WaiterThreads));
    // create and fill waiter threads
    For i := Low(WaiterThreads) to High(WaiterThreads) do
      begin
        If i < High(WaiterThreads) then
          SetLength(ObjectsTemp,MAXIMUM_WAIT_OBJECTS)
        else
          SetLength(ObjectsTemp,Length(Objects) - (Pred(Length(WaiterThreads)) * MAXIMUM_WAIT_OBJECTS));
        For j := Low(ObjectsTemp) to High(ObjectsTemp) do
          ObjectsTemp[j] := Objects[(i * MAXIMUM_WAIT_OBJECTS) + j];
        WaiterThreads[i] := TWaiterThread.Create(ObjectsTemp,WaitAll,Timeout,Alertable,i * MAXIMUM_WAIT_OBJECTS);
        WaiterHandles[i] := WaiterThreads[i].Handle;
      end;
    // wait (do not allow timeout)
    Result := WaitForMultipleHandles(WaiterHandles,True,INFINITE,Index,Alertable);
    // process result
    case Result of
      wrSignaled,
      wrAbandoned:    begin
                        // Check whether all waiter threads ended with result
                        // being signaled or abandoned.
                        For i := Low(WaiterThreads) to High(WaiterThreads) do
                          If WaiterThreads[i].Result > Result then
                            begin
                              Result := WaiterThreads[i].Result;
                              Index := WaiterThreads[i].Index;  // in case it contains an error code
                              If Result = wrError then
                                Break{For i};
                            end;
                      end;  
      wrIOCompletion: Index := -1;
      wrTimeout:      raise EWSOWaitError.Create('WaitForMultipleObjects_High: Wait timeout not allowed here.');
      wrError:        raise EWSOWaitError.CreateFmt('WaitForMultipleObjects_High: Wait error (%d).',[Index]);
    else
     {some nonsensical result, should not happen}
      raise EWSOWaitError.CreateFmt('WaitForMultipleObjects_High: Invalid wait result (%d).',[Ord(Result)]);
    end;
    // free all waiter threads
    For i := Low(WaiterThreads) to High(WaiterThreads) do
      begin
        WaiterThreads[i].WaitFor; // in case wrIOCompletion
        WaiterThreads[i].Free;
      end;
  end
else
  begin
    // first object is expected to be a releaser
    {$message 'implement'}
    Result := wrError;
    Index := -1;
    exit;
  end;
end;

//------------------------------------------------------------------------------

Function WaitForMultipleObjects_Internal(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean): TWaitResult;
begin
If Length(Objects) > MAXIMUM_WAIT_OBJECTS then
  Result := WaitForMultipleObjects_High(Objects,WaitAll,Timeout,Index,Alertable)
else
  Result := WaitForMultipleObjects_Low(Objects,WaitAll,Timeout,Index,Alertable);
end;

{===============================================================================
    Utility functions - public functions
===============================================================================}

Function WaitForMultipleObjects(Objects: array of TWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult;
var
  ObjsTemp: array of TWinSyncObject;
  i:        Integer;
  Releaser: TEvent;
begin
Index := -1;
If Length(Objects) > 0 then
  begin
    If (Length(Objects) > MAXIMUM_WAIT_OBJECTS) and not WaitAll then
      begin
        SetLength(ObjsTemp,Length(Objects) + 1);
        For i := Low(Objects) to High(Objects) do
          ObjsTemp[i + 1] := Objects[i];
        Releaser := TEvent.Create;
        try
          ObjsTemp[Low(ObjsTemp)] := Releaser;
          Result := WaitForMultipleObjects_Internal(ObjsTemp,WaitAll,Timeout,Index,Alertable);
          Releaser.SetEvent;
        finally
          Releaser.Free;
        end;
      end
    else Result := WaitForMultipleObjects_Internal(Objects,WaitAll,Timeout,Index,Alertable);
  end
else raise EWSOMultiWaitInvalidCount.CreateFmt('WaitForMultipleObjects: Invalid object count (%d).',[Length(Objects)]);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TWinSyncObject; Timeout: DWORD; out Index: Integer): TWaitResult;
begin
Result := WaitForMultipleObjects(Objects,False,Timeout,Index);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TWinSyncObject; Timeout: DWORD): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForMultipleObjects(Objects,False,Timeout,Index);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TWinSyncObject): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForMultipleObjects(Objects,False,INFINITE,Index);
end;

//------------------------------------------------------------------------------

Function WaitResultToStr(WaitResult: TWaitResult): String;
const
  WR_STRS: array[TWaitResult] of String = ('Signaled','Abandoned','IOCompletion','Timeout','Error');
begin
Result := WR_STRS[WaitResult];
end;

end.

