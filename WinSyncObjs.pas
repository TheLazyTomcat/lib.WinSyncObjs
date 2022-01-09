{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  WinSyncObjs

    Set of classes encapsulating windows synchronization objects.

  Version 1.2 (2021-09-25)

  Last change 2021-12-21

  ©2016-2022 František Milt

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
    AuxTypes           - github.com/TheLazyTomcat/Lib.AuxTypes
    AuxClasses         - github.com/TheLazyTomcat/Lib.AuxClasses
    NamedSharedItems   - github.com/TheLazyTomcat/Lib.NamedSharedItems
    StrRect            - github.com/TheLazyTomcat/Lib.StrRect
    InterlockedOps     - github.com/TheLazyTomcat/Lib.InterlockedOps
    BitOps             - github.com/TheLazyTomcat/Lib.BitOps    
    HashBase           - github.com/TheLazyTomcat/Lib.HashBase
    SHA1               - github.com/TheLazyTomcat/Lib.SHA1
    StaticMemoryStream - github.com/TheLazyTomcat/Lib.StaticMemoryStream
    SharedMemoryStream - github.com/TheLazyTomcat/Lib.SharedMemoryStream
    UInt64Utils        - github.com/TheLazyTomcat/Lib.UInt64Utils 
  * SimpleCPUID        - github.com/TheLazyTomcat/Lib.SimpleCPUID

  Library SimpleCPUID might not be required, depending on defined symbols in
  InterlockedOps and BitOps libraries.

===============================================================================}
unit WinSyncObjs;

{$IF not(defined(MSWINDOWS) or defined(WINDOWS))}
  {$MESSAGE FATAL 'Unsupported operating system.'}
{$IFEND}

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$MODESWITCH DuplicateLocals+}
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
  AuxTypes, AuxClasses, NamedSharedItems;

{===============================================================================
    Library-specific exceptions
===============================================================================}
type
  EWSOException = class(Exception);

  EWSOInvalidHandle          = class(EWSOException);
  EWSOHandleDuplicationError = class(EWSOException);
  EWSOInvalidObject          = class(EWSOException);
  EWSOOpenError              = class(EWSOException);
  EWSOTimeConversionError    = class(EWSOException);
  EWSOWaitError              = class(EWSOException);
  EWSOUnsupportedObject      = class(EWSOException);
  EWSOAutoCycleError         = class(EWSOException);
  EWSOInvalidValue           = class(EWSOException);
  EWSOMultiWaitInvalidCount  = class(EWSOException);

{===============================================================================
--------------------------------------------------------------------------------
                                TCriticalSection
--------------------------------------------------------------------------------
===============================================================================}
{
  To properly use the TCriticalSection object, create one instance and then
  pass this one instance to other threads that need to be synchronized.

  Make sure to only free it once.

  You can also set the proterty FreeOnRelease to true (by default false) and
  then use the build-in reference counting - call method Acquire for each
  thread using it (including the one that created it) and method Release every
  time a thread will stop using it. When reference count reaches zero in a
  call to Release, the object will be automatically freed.
}
{===============================================================================
    TCriticalSection - class declaration
===============================================================================}
type
  TCriticalSection = class(TCustomRefCountedObject)
  private
    fCriticalSectionObj:  TRTLCriticalSection;
    fSpinCount:           DWORD;
    Function GetSpinCount: DWORD;
    procedure SetSpinCountProc(Value: DWORD); // only redirector to SetSpinCount (setter cannot be a function)
  public
    constructor Create; overload;
    constructor Create(SpinCount: DWORD); overload;
    destructor Destroy; override;
    Function SetSpinCount(SpinCount: DWORD): DWORD;
    Function TryEnter: Boolean;
    procedure Enter;
    procedure Leave;
  {
    If you are setting SpinCount in multiple threads, then the property might
    not necessarily contain the correct value set for the underlying system
    object.
    Set this property only in one thread or use it only for reading the value
    that was set in the constructor.
  }
    property SpinCount: DWORD read GetSpinCount write SetSpinCountProc;
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
    Function RectifyAndSetName(const Name: String): Boolean; virtual;
  public
    constructor Create;
  {
    LastError contains code of the last operating system error that has not
    resulted in an exception being raised (eg. error during waiting, release
    operations, ...).
  }
    property LastError: DWORD read fLastError;
    property Name: String read fName;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                              TSimpleWinSyncObject
--------------------------------------------------------------------------------
===============================================================================}
{
  To properly use simple windows synchronization object (TEvent, TMutex,
  TSemaphore, TWaitableTimer), create one progenitor instance and use this one
  instance only in a thread where it was created. Note that it IS possible and
  permissible to use the same instance in multiple threads, but this practice
  is discouraged as none of the fields are protected against concurrent access
  (especially problematic for LastError property).

  To access the synchronizer in other threads of the same process, create a new
  instance using DuplicateFrom constructor, passing the progenitor instance or
  any duplicate instance based on it.
  You can also use Open constructors where implemented and when the object is
  created with a name.

  To access the synchronizer in different process, it is recommended to use
  Open constructors (requires named object).
  DuplicateFromProcess constructors or DuplicateForProcess methods along with
  CreateFrom constructor can also be used, but this requires some kind of IPC
  to transfer the handles between processes.
}
{
  wrFatal is only used internally, and should not be returned by any public
  funtion. If it still is, you should treat it as really serious error.
}
type
  TWaitResult = (wrSignaled, wrAbandoned, wrIOCompletion, wrMessage, wrTimeout, wrError, wrFatal);

{===============================================================================
    TSimpleWinSyncObject - class declaration
===============================================================================}
type
  TSimpleWinSyncObject = class(TWinSyncObject)
  protected
    fHandle:  THandle;
    Function RectifyAndSetName(const Name: String): Boolean; override;
    procedure CheckAndSetHandle(Handle: THandle); virtual;
    procedure DuplicateAndSetHandle(SourceProcess: THandle; SourceHandle: THandle); virtual;
  public
    constructor CreateFrom(Handle: THandle{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF});
    constructor DuplicateFrom(SourceHandle: THandle); overload;
    constructor DuplicateFrom(SourceObject: TSimpleWinSyncObject); overload;
  {
    When passing handle from 32bit process to 64bit process, it is safe to
    zero or sign-extend it. In the opposite direction, it is safe to truncate
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
const
  // constants for DesiredAccess parameter of Open constructor
  EVENT_MODIFY_STATE = 2;
  EVENT_ALL_ACCESS   = STANDARD_RIGHTS_REQUIRED or SYNCHRONIZE or 3;

{===============================================================================
    TEvent - class declaration
===============================================================================}
type
  TEvent = class(TSimpleWinSyncObject)
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; ManualReset, InitialState: Boolean; const Name: String); overload;
    constructor Create(ManualReset, InitialState: Boolean; const Name: String); overload;
    constructor Create(const Name: String); overload; // ManualReset := True, InitialState := False
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
const
  MUTANT_QUERY_STATE = 1;
  MUTANT_ALL_ACCESS  = STANDARD_RIGHTS_REQUIRED or SYNCHRONIZE or MUTANT_QUERY_STATE;

  MUTEX_MODIFY_STATE = MUTANT_QUERY_STATE;
  MUTEX_ALL_ACCESS   = MUTANT_ALL_ACCESS;

{===============================================================================
    TMutex - class declaration
===============================================================================}
type
  TMutex = class(TSimpleWinSyncObject)
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; InitialOwner: Boolean; const Name: String); overload;
    constructor Create(InitialOwner: Boolean; const Name: String); overload;
    constructor Create(const Name: String); overload; // InitialOwner := False
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
const
  SEMAPHORE_MODIFY_STATE = 2;
  SEMAPHORE_ALL_ACCESS   = STANDARD_RIGHTS_REQUIRED or SYNCHRONIZE or 3;
  
{===============================================================================
    TSemaphore - class declaration
===============================================================================}
type
  TSemaphore = class(TSimpleWinSyncObject)
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; InitialCount, MaximumCount: Integer; const Name: String); overload;
    constructor Create(InitialCount, MaximumCount: Integer; const Name: String); overload;
    constructor Create(const Name: String); overload; // InitialCount := 1, MaximumCount := 1
    constructor Create; overload;
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
const
  TIMER_QUERY_STATE  = 1;
  TIMER_MODIFY_STATE = 2;
  TIMER_ALL_ACCESS   = STANDARD_RIGHTS_REQUIRED or SYNCHRONIZE or TIMER_QUERY_STATE or TIMER_MODIFY_STATE;

{===============================================================================
    TWaitableTimer - class declaration
===============================================================================}
type
  TTimerAPCRoutine = procedure(ArgToCompletionRoutine: Pointer; TimerLowValue, TimerHighValue: DWORD); stdcall;
  PTimerAPCRoutine = ^TTimerAPCRoutine;

  TWaitableTimer = class(TSimpleWinSyncObject)
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; ManualReset: Boolean; const Name: String); overload;
    constructor Create(ManualReset: Boolean; const Name: String); overload;
    constructor Create(const Name: String); overload; // ManualReset := True
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
                              TComplexWinSyncObject
--------------------------------------------------------------------------------
===============================================================================}
{
  Complex synchronization objects can be principally created in two ways - as
  thread-shared or process-shared.

  Thread-shared objects are created without a name, or, more precisely, with an
  empty name. They can be used only for synchronization between threads within
  one process.

  Process-shared objects are created with non-empty name and can be used for
  synchronization between any threads within a system, including threads in
  different processes.
  Two instances with the same name, created in any process, will be using the
  same synchronization object. Different types of synchronizers can have the
  same name and still be considered separate, so there is no risk of naming
  conflicts (each type of synchronizer has kind-of its own namespace).

    WARNING - TConditionVariable and TConditionVariableEx are considered one
              type of synchronizer, the latter being only an extension of the
              former, so they occupy the same namespace. But it is NOT possible
              to create an instace of TConditionVariableEx by opening (using
              Open or DuplicateFrom constructor) instance of TConditionVariable.


  To properly use complex windows synchronization object (TConditioVariable,
  TConditioVariableEx, TBarrier, TReadWriteLock), create one progenitor
  instance and use this instance only in the thread that created it.

  To access the synchronizer in other threads of the same process, create a new
  instance using DuplicateFrom constructor, passing the progenitor instance or
  any duplicate instance based on it as a source. If the progenitor is
  process-shared (ie. named), you can also open it using Create or Open
  construtors, specifying the same name as has the progenitor.

  To access the synchronizer in different process, the progenitor must be
  created as process-shared, that is, it must have a non-empty name. Use Create
  or Open constructors, specifying the same name as has the progenitor.
  The newly created instances will then be using the same synchronization object
  as the progenitor.

    NOTE - DuplicateFrom constructor can be used on both thread-shared and
           process-shared source object, the newly created instance will have
           the same mode as source. For process-shared (named) objects, calling
           this constructor is equivalent to caling Open constructor.
}
type
  TWSOSharedUserData = packed array[0..31] of Byte;
  PWSOSharedUserData = ^TWSOSharedUserData;

  TWSOSharedDataLock = record
    case Boolean of
      True:   (ProcessSharedLock: THandle);
      False:  (ThreadSharedLock:  TCriticalSection);
  end;

  // all object shared data must start with this structure
  TWSOCommonSharedData = packed record
    SharedUserData: TWSOSharedUserData;
    RefCount:       Int32;                // used only in thread-shared mode
  end;
  PWSOCommonSharedData = ^TWSOCommonSharedData;

{===============================================================================
    TComplexWinSyncObject - class declaration
===============================================================================}
type
  TComplexWinSyncObject = class(TWinSyncObject)
  protected
    fProcessShared:   Boolean;
    fSharedDataLock:  TWSOSharedDataLock;
    fNamedSharedItem: TNamedSharedItem;   // unused in thread-shared mode
    fSharedData:      Pointer;
    Function GetSharedUserDataPtr: PWSOSharedUserData; virtual;
    Function GetSharedUserData: TWSOSharedUserData; virtual;
    procedure SetSharedUserData(Value: TWSOSharedUserData); virtual;
    Function RectifyAndSetName(const Name: String): Boolean; override;
    procedure CheckAndSetHandle(out Destination: THandle; Handle: THandle); virtual;
    procedure DuplicateAndSetHandle(out Destination: THandle; Handle: THandle); virtual;
    // shared data lock management methods
    class Function GetSharedDataLockSuffix: String; virtual; abstract;
    procedure CreateSharedDataLock(SecurityAttributes: PSecurityAttributes); virtual;
    procedure OpenSharedDataLock(DesiredAccess: DWORD; InheritHandle: Boolean); virtual;
    procedure DestroySharedDataLock; virtual;
    procedure LockSharedData; virtual;
    procedure UnlockSharedData; virtual;
    // shared data management methods
    procedure AllocateSharedData; virtual;
    procedure FreeSharedData; virtual;
    // locks management methods (internal workings)
    procedure CreateLocks(SecurityAttributes: PSecurityAttributes); virtual; abstract;
    procedure OpenLocks(DesiredAccess: DWORD; InheritHandle: Boolean); virtual; abstract;
    procedure DuplicateLocks(SourceObject: TComplexWinSyncObject); virtual; abstract; // should also set class-specific shared data pointer
    procedure DestroyLocks; virtual; abstract;
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; const Name: String); overload; virtual;
    constructor Create(const Name: String); overload; virtual;
    constructor Create; overload; virtual;
    constructor Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String); overload; virtual;
    constructor Open(const Name: String{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF}); overload; virtual;
  {
    Use DuplicateFrom to create instance that accesses the same synchronization
    primitive(s) and shared data as the source object.

    If the source object is process-shared, DuplicateFrom is equivalent to Open
    constructor.

    WARNING - duplication is NOT thread safe, make sure you do not free the
              duplicated object before the duplication finishes (constructor
              returns).
  }
    constructor DuplicateFrom(SourceObject: TComplexWinSyncObject); virtual;
    destructor Destroy; override;
    property ProcessShared: Boolean read fProcessShared;
    property SharedUserDataPtr: PWSOSharedUserData read GetSharedUserDataPtr;
    property SharedUserData: TWSOSharedUserData read GetSharedUserData write SetSharedUserData;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                               TConditionVariable
--------------------------------------------------------------------------------
===============================================================================}
{
  WARNING - be wery cautious about objects passed as DataLock parameter to
            methods Sleep and AutoCycle. If they have been locked multiple
            times before the call (affects mutexes and semaphores), it can
            create a deadlock as the lock is released only once within the
            method (so it can effectively stay locked indefinitely).
}
type
  TWSOCondSharedData = packed record
    SharedUserData: TWSOSharedUserData;
    RefCount:       Int32;
    WaitCount:      Int32;
    WakeCount:      Int32;
    Broadcasting:   Boolean;
  end;
  PWSOCondSharedData = ^TWSOCondSharedData;

  // types for autocycle
  TWSOWakeOption = (woWakeOne,woWakeAll,woWakeBeforeUnlock);
  TWSOWakeOptions = set of TWSOWakeOption;

  TWSOPredicateCheckEvent = procedure(Sender: TObject; var Predicate: Boolean) of object;
  TWSOPredicateCheckCallback = procedure(Sender: TObject; var Predicate: Boolean);

  TWSODataAccessEvent = procedure(Sender: TObject; var WakeOptions: TWSOWakeOptions) of object;
  TWSODataAccessCallback = procedure(Sender: TObject; var WakeOptions: TWSOWakeOptions);

{===============================================================================
    TConditionVariable - class declaration
===============================================================================}
type
  TConditionVariable = class(TComplexWinSyncObject)
  protected
    fWaitLock:                  THandle;              // semaphore
    fBroadcastDoneLock:         THandle;              // autoreset event
    fCondSharedData:            PWSOCondSharedData;
    // autocycle events
    fOnPredicateCheckEvent:     TWSOPredicateCheckEvent;
    fOnPredicateCheckCallback:  TWSOPredicateCheckCallback;
    fOnDataAccessEvent:         TWSODataAccessEvent;
    fOnDataAccessCallback:      TWSODataAccessCallback;
    class Function GetSharedDataLockSuffix: String; override;
    // shared data management methods
    procedure AllocateSharedData; override;
    procedure FreeSharedData; override;
    // locks management methods
    procedure CreateLocks(SecurityAttributes: PSecurityAttributes); override;
    procedure OpenLocks(DesiredAccess: DWORD; InheritHandle: Boolean); override;
    procedure DuplicateLocks(SourceObject: TComplexWinSyncObject); override;
    procedure DestroyLocks; override;
    // autocycle events firing
    Function DoOnPredicateCheck: Boolean; virtual;
    Function DoOnDataAccess: TWSOWakeOptions; virtual;
    // utility methods
    procedure SelectWake(WakeOptions: TWSOWakeOptions); virtual;
  public
  {
    In both overloads, DataLock parameter can only be an event, mutex or
    semaphore, no other type of synchronizer is supported.
  }
    procedure Sleep(DataLock: THandle; Timeout: DWORD = INFINITE; Alertable: Boolean = False); overload; virtual;
    procedure Sleep(DataLock: TSimpleWinSyncObject; Timeout: DWORD = INFINITE; Alertable: Boolean = False); overload; virtual;
    procedure Wake; virtual;
    procedure WakeAll; virtual;
  {
    First overload of AutoCycle method only supports mutex object as DataLock
    parameter - it is because the object must be signaled and different objects
    have different functions for that, and there is no way of discerning which
    object is hidden behind the handle.
    ...well, there is a way, but it involves function NtQueryObject which
    should not be used in application code, so let's avoid it.

    Second overload allows for event, mutex and semaphore object to be used
    as data synchronizer.
  }
    procedure AutoCycle(DataLock: THandle); overload; virtual;
    procedure AutoCycle(DataLock: TSimpleWinSyncObject); overload; virtual;
    // events
    property OnPredicateCheckEvent: TWSOPredicateCheckEvent read fOnPredicateCheckEvent write fOnPredicateCheckEvent;
    property OnPredicateCheckCallback: TWSOPredicateCheckCallback read fOnPredicateCheckCallback write fOnPredicateCheckCallback;
    property OnPredicateCheck: TWSOPredicateCheckEvent read fOnPredicateCheckEvent write fOnPredicateCheckEvent;
    property OnDataAccessEvent: TWSODataAccessEvent read fOnDataAccessEvent write fOnDataAccessEvent;    
    property OnDataAccessCallback: TWSODataAccessCallback read fOnDataAccessCallback write fOnDataAccessCallback;
    property OnDataAccess: TWSODataAccessEvent read fOnDataAccessEvent write fOnDataAccessEvent;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                              TConditionVariableEx
--------------------------------------------------------------------------------
===============================================================================}
{
  Only an extension of TConditionVariable with integrated data lock (use methods
  Lock and Unlock to manipulate it). New versions of methods Sleep and AutoCycle
  without the DataLock parameter are using the integrated data lock for that
  purpose.

    WARNING - as in the case of TConditionVariable, be wary of how many times
              you lock the integrated data lock. A mutex is used internally, so
              mutliple locks can result in a deadlock in sleep method.
}
{===============================================================================
    TConditionVariableEx - class declaration
===============================================================================}
type
  TConditionVariableEx = class(TConditionVariable)
  protected
    fDataLock:  THandle;  // mutex
    procedure CreateLocks(SecurityAttributes: PSecurityAttributes); override;
    procedure OpenLocks(DesiredAccess: DWORD; InheritHandle: Boolean); override;
    procedure DuplicateLocks(SourceObject: TComplexWinSyncObject); override;
    procedure DestroyLocks; override;    
  public
    procedure Lock; virtual;
    procedure Unlock; virtual;
    procedure Sleep(Timeout: DWORD = INFINITE; Alertable: Boolean = False); overload; virtual;
    procedure AutoCycle; overload; virtual; // uses internal data synchronizer
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                    TBarrier
--------------------------------------------------------------------------------
===============================================================================}
type
  TWSOBarrierSharedData = packed record
    SharedUserData: TWSOSharedUserData;
    RefCount:       Int32;
    MaxWaitCount:   Int32;  // invariant value, set only once
    WaitCount:      Int32;
    Releasing:      Boolean;
  end;
  PWSOBarrierSharedData = ^TWSOBarrierSharedData;

{===============================================================================
    TBarrier - class declaration
===============================================================================}
type
  TBarrier = class(TComplexWinSyncObject)
  protected
    fReleaseLock:       THandle;                // manual-reset event
    fWaitLock:          THandle;                // manual-reset event
    fBarrierSharedData: PWSOBarrierSharedData;
    Function GetCount: Integer; virtual;
    class Function GetSharedDataLockSuffix: String; override;
    // shared data management methods
    procedure AllocateSharedData; override;
    procedure FreeSharedData; override;
    // locks management methods
    procedure CreateLocks(SecurityAttributes: PSecurityAttributes); override;
    procedure OpenLocks(DesiredAccess: DWORD; InheritHandle: Boolean); override;
    procedure DuplicateLocks(SourceObject: TComplexWinSyncObject); override;
    procedure DestroyLocks; override;
  public
    constructor Create(SecurityAttributes: PSecurityAttributes; const Name: String); override;
    constructor Create(const Name: String); override;
    constructor Create; override;
    constructor Create(SecurityAttributes: PSecurityAttributes; Count: Integer; const Name: String); overload;
    constructor Create(Count: Integer; const Name: String); overload;
    constructor Create(Count: Integer); overload;
    Function Wait: Boolean; virtual;
  {
    Releases all waiting threads, irrespective of their count, and sets the
    barrier back to a non-signaled (blocking) state.  
  }
    Function Release: Integer; virtual;
    property Count: Integer read GetCount;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                 TReadWriteLock
--------------------------------------------------------------------------------
===============================================================================}
{
  This implementation of read-write lock allows for recursive locking, both for
  readers and writers, but it does not support read lock promotion - that is,
  you cannot acquire write lock in the same thread where you are holding a read
  lock.

    WARNING - trying to acquire write lock in a thread that is currently holding
              a read lock (or vice-versa) will inevitably create a deadlock.
}
type
  TWSORWLockSharedData = packed record
    SharedUserData: TWSOSharedUserData;
    RefCount:       Int32;

  end;
  PWSORWLockSharedData = ^TWSORWLockSharedData;

{===============================================================================
    TReadWriteLock - class declaration
===============================================================================}
type
  TReadWriteLock = class(TComplexWinSyncObject)
  protected
  public
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                 Wait functions
--------------------------------------------------------------------------------
===============================================================================}
type
{
  Options for message waiting. See MsgWaitForMultipleObjects(Ex) documentation
  for details of message waiting.

  mwoEnable         - enable waiting on messages
  mwoInputAvailable - adds MWMO_INPUTAVAILABLE to flags when message waiting
                      is enabled.
}
  TMessageWaitOption = (mwoEnable,mwoInputAvailable);

  TMessageWaitOptions = set of TMessageWaitOption;

{
  Currently defined values for WakeMask parameter.
}
const
  QS_KEY            = $0001;
  QS_MOUSEMOVE      = $0002;
  QS_MOUSEBUTTON    = $0004;
  QS_POSTMESSAGE    = $0008;
  QS_TIMER          = $0010;
  QS_PAINT          = $0020;
  QS_SENDMESSAGE    = $0040;
  QS_HOTKEY         = $0080;
  QS_ALLPOSTMESSAGE = $0100;
  QS_RAWINPUT       = $0400;
  QS_TOUCH          = $0800;
  QS_POINTER        = $1000;
  QS_MOUSE          = QS_MOUSEMOVE or QS_MOUSEBUTTON;
  QS_INPUT          = QS_MOUSE or QS_KEY or QS_RAWINPUT or QS_TOUCH or QS_POINTER;
  QS_ALLEVENTS      = QS_INPUT or QS_POSTMESSAGE or QS_TIMER or QS_PAINT or QS_HOTKEY;
  QS_ALLINPUT       = QS_INPUT or QS_POSTMESSAGE or QS_TIMER or QS_PAINT or QS_HOTKEY or QS_SENDMESSAGE;

//------------------------------------------------------------------------------
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

  Handle array must not be empty and length (Count) must be less or equal to 64
  (63 when message waiting is enabled), otherwise an exception of type
  EWSOMultiWaitInvalidCount will be raised.

  If WaitAll is set to true, the function will return wrSignaled only when ALL
  objects are signaled. When set to false, it will return wrSignaled when at
  least one object becomes signaled.

  Timeout is in milliseconds. Default value for Timeout is INFINITE.

  When WaitAll is false, Index indicates which object was signaled or abandoned
  when wrSignaled or wrAbandoned is returned. In case of wrError, the Index
  contains a system error number. For other results, the value of Index is
  undefined.
  When WaitAll is true, value of Index is undefined except for wrError, where
  it again contains system error number.

  If Alertable is true, the function will also return if APC has been queued
  to the waiting thread. Default value for Alertable is False.

  Use set argument MsgWaitOptions to enable and configure message waiting.
  Default value is an empty set, meaning message waiting is disabled.

  Argument WakeMask is used without change when message waiting is enabled
  (it prescribes which messages to observe), otherwise it is ignored. Use OR
  to combine multiple values. Default value is zero.
}
Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD = QS_ALLINPUT): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}

//------------------------------------------------------------------------------
{
  Following functions are behaving the same as the ones accepting pointer to
  handle array, see there for details.
}
Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD = QS_ALLINPUT): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}

//------------------------------------------------------------------------------
{
  Functions WaitForMultipleObjects are, again, behaving exactly the same as
  WaitForMultipleHandles.

    NOTE - LastError property of the passed objects is not set by these
           functions. Possible error code is returned in Index output parameter.
}
Function WaitForMultipleObjects(Objects: array of TSimpleWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD = QS_ALLINPUT): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleObjects(Objects: array of TSimpleWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleObjects(Objects: array of TSimpleWinSyncObject; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForMultipleObjects(Objects: array of TSimpleWinSyncObject; WaitAll: Boolean): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}

//------------------------------------------------------------------------------

Function WaitForManyHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD = QS_ALLINPUT): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForManyHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForManyHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForManyHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}

//------------------------------------------------------------------------------

Function WaitForManyHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD = QS_ALLINPUT): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForManyHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForManyHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}
Function WaitForManyHandles(Handles: array of THandle; WaitAll: Boolean): TWaitResult; overload;{$IFDEF CanInline} inline;{$ENDIF}


{===============================================================================
--------------------------------------------------------------------------------
                               Utility functions
--------------------------------------------------------------------------------
===============================================================================}
{
  WaitResultToStr simply returns textual representation of a given wait result.

  It is meant mainly for debugging purposes.
}
Function WaitResultToStr(WaitResult: TWaitResult): String;

implementation

uses
  Classes, Math,
  StrRect, InterlockedOps, UInt64Utils;

{$IFDEF FPC_DisableWarns}
  {$DEFINE FPCDWM}
  {$DEFINE W5057:={$WARN 5057 OFF}} // Local variable "$1" does not seem to be initialized
  {$DEFINE W5058:={$WARN 5058 OFF}} // Variable "$1" does not seem to be initialized
{$ENDIF}

{===============================================================================
    Internals
===============================================================================}
{$IF not Declared(UNICODE_STRING_MAX_CHARS)}
const
  UNICODE_STRING_MAX_CHARS = 32767;
{$IFEND}

//------------------------------------------------------------------------------
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

Function TCriticalSection.GetSpinCount: DWORD;
begin
Result := InterlockedLoad(fSpinCount);
end;

//------------------------------------------------------------------------------

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

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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
InterlockedStore(fSpinCount,SpinCount);
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

Function TWinSyncObject.RectifyAndSetName(const Name: String): Boolean;
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

Function TSimpleWinSyncObject.RectifyAndSetName(const Name: String): Boolean;
begin
inherited RectifyAndSetName(Name);  // only sets the fName field
{
  Names should not contain backslashes (\, #92), but they can separate
  prefixes, so in theory they are allowed - do not replace them, leave this
  responsibility on the user.

  Wide-string version of WinAPI functions are used, but there is still strict
  limit of 32767 wide characters in a string.
}
If Length(fName) > UNICODE_STRING_MAX_CHARS then
  SetLength(fName,UNICODE_STRING_MAX_CHARS);
Result := Length(fName) > 0;
end;

//------------------------------------------------------------------------------

procedure TSimpleWinSyncObject.CheckAndSetHandle(Handle: THandle);
begin
If Handle <> 0 then
  fHandle := Handle
else
  raise EWSOInvalidHandle.CreateFmt('TSimpleWinSyncObject.CheckAndSetHandle: Null handle (0x%.8x).',[GetLastError]);
end;

//------------------------------------------------------------------------------

procedure TSimpleWinSyncObject.DuplicateAndSetHandle(SourceProcess: THandle; SourceHandle: THandle);
var
  NewHandle:  THandle;
begin
If DuplicateHandle(SourceProcess,SourceHandle,GetCurrentProcess,@NewHandle,0,False,DUPLICATE_SAME_ACCESS) then
  CheckAndSetHandle(NewHandle)
else
  raise EWSOHandleDuplicationError.CreateFmt('TSimpleWinSyncObject.DuplicateAndSetHandleFrom: ' +
                                             'Handle duplication failed (0x%.8x).',[GetLastError]);
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
inherited Create;
DuplicateAndSetHandle(GetCurrentProcess,SourceHandle);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TSimpleWinSyncObject.DuplicateFrom(SourceObject: TSimpleWinSyncObject);
begin
inherited Create;
If SourceObject is Self.ClassType then
  DuplicateAndSetHandle(GetCurrentProcess,SourceObject.Handle)
else
  raise EWSOInvalidObject.CreateFmt('TSimpleWinSyncObject.DuplicateFrom: Incompatible source object (%s).',[SourceObject.ClassName]);
end;

//------------------------------------------------------------------------------

constructor TSimpleWinSyncObject.DuplicateFromProcess(SourceProcess: THandle; SourceHandle: THandle);
begin
inherited Create;
DuplicateAndSetHandle(SourceProcess,SourceHandle);
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
    DuplicateAndSetHandle(SourceProcess,SourceHandle);
  finally
    CloseHandle(SourceProcess);
  end
else raise EWSOHandleDuplicationError.CreateFmt('TSimpleWinSyncObject.DuplicateFromProcessID: ' +
                                                'Failed to open source process (0x%.8x).',[GetLastError]);
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
  raise EWSOHandleDuplicationError.CreateFmt('TSimpleWinSyncObject.DuplicateForProcess: ' +
                                             'Handle duplication failed (0x%.8x).',[GetLastError]);
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
else raise EWSOHandleDuplicationError.CreateFmt('TSimpleWinSyncObject.DuplicateForProcessID: ' +
                                                'Failed to open target process (0x%.8x).',[GetLastError]);
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
If RectifyAndSetName(Name) then
  CheckAndSetHandle(CreateEventW(SecurityAttributes,ManualReset,InitialState,PWideChar(StrToWide(fName))))
else
  CheckAndSetHandle(CreateEventW(SecurityAttributes,ManualReset,InitialState,nil));
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TEvent.Create(ManualReset, InitialState: Boolean; const Name: String);
begin
Create(nil,ManualReset,InitialState,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TEvent.Create(const Name: String);
begin
Create(nil,True,False,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TEvent.Create;
begin
Create(nil,True,False,'');
end;

//------------------------------------------------------------------------------

constructor TEvent.Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String);
begin
inherited Create;
If RectifyAndSetName(Name) then
  CheckAndSetHandle(OpenEventW(DesiredAccess,InheritHandle,PWideChar(StrToWide(fName))))
else
  raise EWSOOpenError.Create('TEvent.Open: Empty name not allowed.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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
If RectifyAndSetName(Name) then
  CheckAndSetHandle(CreateMutexW(SecurityAttributes,RectBool(InitialOwner),PWideChar(StrToWide(fName))))
else
  CheckAndSetHandle(CreateMutexW(SecurityAttributes,RectBool(InitialOwner),nil));
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TMutex.Create(InitialOwner: Boolean; const Name: String);
begin
Create(nil,InitialOwner,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TMutex.Create(const Name: String);
begin
Create(nil,False,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TMutex.Create;
begin
Create(nil,False,'');
end;

//------------------------------------------------------------------------------

constructor TMutex.Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String);
begin
inherited Create;
If RectifyAndSetName(Name) then
  CheckAndSetHandle(OpenMutexW(DesiredAccess,InheritHandle,PWideChar(StrToWide(fName))))
else
  raise EWSOOpenError.Create('TMutex.Open: Empty name not allowed.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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
If RectifyAndSetName(Name) then
  CheckAndSetHandle(CreateSemaphoreW(SecurityAttributes,InitialCount,MaximumCount,PWideChar(StrToWide(fName))))
else
  CheckAndSetHandle(CreateSemaphoreW(SecurityAttributes,InitialCount,MaximumCount,nil));
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TSemaphore.Create(InitialCount, MaximumCount: Integer; const Name: String);
begin
Create(nil,InitialCount,MaximumCount,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TSemaphore.Create(const Name: String);
begin
Create(nil,1,1,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TSemaphore.Create;
begin
Create(nil,1,1,'');
end;

//------------------------------------------------------------------------------

constructor TSemaphore.Open(DesiredAccess: LongWord; InheritHandle: Boolean; const Name: String);
begin
inherited Create;
If RectifyAndSetName(Name) then
  CheckAndSetHandle(OpenSemaphoreW(DesiredAccess,InheritHandle,PWideChar(StrToWide(fName))))
else
  raise EWSOOpenError.Create('TSemaphore.Open: Empty name not allowed.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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
If RectifyAndSetName(Name) then
  CheckAndSetHandle(CreateWaitableTimerW(SecurityAttributes,ManualReset,PWideChar(StrToWide(fName))))
else
  CheckAndSetHandle(CreateWaitableTimerW(SecurityAttributes,ManualReset,nil));
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TWaitableTimer.Create(ManualReset: Boolean; const Name: String);
begin
Create(nil,ManualReset,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TWaitableTimer.Create(const Name: String);
begin
Create(nil,True,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TWaitableTimer.Create;
begin
Create(nil,True,'');
end;

//------------------------------------------------------------------------------

constructor TWaitableTimer.Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String);
begin
inherited Create;
If RectifyAndSetName(Name) then
  CheckAndSetHandle(OpenWaitableTimerW(DesiredAccess,InheritHandle,PWideChar(StrToWide(fName))))
else
  raise EWSOOpenError.Create('TWaitableTimer.Open: Empty name not allowed.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TWaitableTimer.SetWaitableTimer(DueTime: Int64; Period: Integer = 0): Boolean;
begin
Result := SetWaitableTimer(DueTime,Period,nil,nil,False);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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
                                                  'LocalFileTimeToFileTime failed (0x%.8x).',[GetLastError]);
      end
    else raise EWSOTimeConversionError.CreateFmt('TWaitableTimer.SetWaitableTimer.DateTimeToFileTime: ' +
                                                 'SystemTimeToFileTime failed (0x%.8x).',[GetLastError]);
  end;

begin
Result := SetWaitableTimer(Int64(DateTimeToFileTime(DueTime)),Period,CompletionRoutine,ArgToCompletionRoutine,Resume);
If not Result then
  fLastError := GetLastError;
end;
{$IFDEF FPCDWM}{$POP}{$ENDIF}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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
                              TComplexWinSyncObject
--------------------------------------------------------------------------------
===============================================================================}
const
  WSO_CPLX_SHARED_NAMESPACE = 'wso_shared';
{$IF SizeOf(TWSOCondSharedData) > SizeOf(TWSOBarrierSharedData)}
  WSO_CPLX_SHARED_ITEMSIZE  = SizeOf(TWSOCondSharedData);
{$ELSE}
  WSO_CPLX_SHARED_ITEMSIZE  = SizeOf(TWSOBarrierSharedData);   
{$IFEND}

  WSO_CPLX_SUFFIX_LENGTH = 8; // all suffixes must have the same length

// because there are incorrect declarations...
Function SignalObjectAndWait(hObjectToSignal: THandle; hObjectToWaitOn: THandle; dwMilliseconds: DWORD; bAlertable: BOOL): DWORD; stdcall; external kernel32;

{===============================================================================
    TComplexWinSyncObject - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TComplexWinSyncObject - protected methods
-------------------------------------------------------------------------------}

Function TComplexWinSyncObject.GetSharedUserDataPtr: PWSOSharedUserData;
begin
Result := Addr(PWSOCommonSharedData(fSharedData)^.SharedUserData);
end;

//------------------------------------------------------------------------------

Function TComplexWinSyncObject.GetSharedUserData: TWSOSharedUserData;
begin
Move(GetSharedUserDataPtr^,Addr(Result)^,SizeOf(TWSOSharedUserData));
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.SetSharedUserData(Value: TWSOSharedUserData);
begin
Move(Value,GetSharedUserDataPtr^,SizeOf(TWSOSharedUserData));
end;

//------------------------------------------------------------------------------

Function TComplexWinSyncObject.RectifyAndSetName(const Name: String): Boolean;
begin
inherited RectifyAndSetName(Name);  // should be always true
If (Length(fName) + WSO_CPLX_SUFFIX_LENGTH) > UNICODE_STRING_MAX_CHARS then
  SetLength(fName,UNICODE_STRING_MAX_CHARS - WSO_CPLX_SUFFIX_LENGTH);
Result := Length(fName) > 0;
fProcessShared := Result;
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.CheckAndSetHandle(out Destination: THandle; Handle: THandle);
begin
If Handle <> 0 then
  Destination := Handle
else
  raise EWSOInvalidHandle.CreateFmt('TComplexWinSyncObject.CheckAndSetHandle: Null handle (0x%.8x).',[GetLastError]);
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.DuplicateAndSetHandle(out Destination: THandle; Handle: THandle);
var
  NewHandle:  THandle;
begin
If DuplicateHandle(GetCurrentProcess,Handle,GetCurrentProcess,@NewHandle,0,False,DUPLICATE_SAME_ACCESS) then
  CheckAndSetHandle(Destination,NewHandle)
else
  raise EWSOHandleDuplicationError.CreateFmt('TComplexWinSyncObject.DuplicateAndSetHandle: ' +
                                             'Handle duplication failed (0x%.8x).',[GetLastError]);
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.CreateSharedDataLock(SecurityAttributes: PSecurityAttributes);
begin
If fProcessShared then
  begin
    CheckAndSetHandle(fSharedDataLock.ProcessSharedLock,
      CreateMutexW(SecurityAttributes,RectBool(False),PWideChar(StrToWide(fName + GetSharedDataLockSuffix))));
  end
else
  begin
    fSharedDataLock.ThreadSharedLock := TCriticalSection.Create;
    fSharedDataLock.ThreadSharedLock.FreeOnRelease := True;
    fSharedDataLock.ThreadSharedLock.Acquire;
  end;
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.OpenSharedDataLock(DesiredAccess: DWORD; InheritHandle: Boolean);
begin
CheckAndSetHandle(fSharedDataLock.ProcessSharedLock,
  OpenMutexW(DesiredAccess or MUTEX_MODIFY_STATE,InheritHandle,PWideChar(StrToWide(fName + GetSharedDataLockSuffix))));
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.DestroySharedDataLock;
begin
If fProcessShared then
  CloseHandle(fSharedDataLock.ProcessSharedLock)
else
  If Assigned(fSharedDataLock.ThreadSharedLock) then
    fSharedDataLock.ThreadSharedLock.Release; // auto-free should be on
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.LockSharedData;
begin
If fProcessShared then
  begin
    If not(WaitForSingleObject(fSharedDataLock.ProcessSharedLock,INFINITE) in [WAIT_OBJECT_0,WAIT_ABANDONED]) then
      raise EWSOWaitError.Create('TComplexWinSyncObject.LockSharedData: Lock not acquired, cannot proceed.');
  end
else fSharedDataLock.ThreadSharedLock.Enter;
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.UnlockSharedData;
begin
If fProcessShared then
  begin
    If not ReleaseMutex(fSharedDataLock.ProcessSharedLock) then
      raise EWSOWaitError.CreateFmt('TComplexWinSyncObject.UnlockSharedData: Lock not released, cannot proceed (0x%.8x).',[GetLastError]);
  end
else fSharedDataLock.ThreadSharedLock.Leave;
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.AllocateSharedData;
begin
If fProcessShared then
  begin
    fNamedSharedItem := TNamedSharedItem.Create(fName,WSO_CPLX_SHARED_ITEMSIZE,WSO_CPLX_SHARED_NAMESPACE);
    fSharedData := fNamedSharedItem.Memory;
  end
else
  begin
    fSharedData := AllocMem(WSO_CPLX_SHARED_ITEMSIZE);
    InterlockedStore(PWSOCommonSharedData(fSharedData)^.RefCount,1);
  end;
end;

//------------------------------------------------------------------------------

procedure TComplexWinSyncObject.FreeSharedData;
begin
If Assigned(fSharedData) then
  begin
    If fProcessShared then
      begin
        If Assigned(fNamedSharedItem) then
          FreeAndNil(fNamedSharedItem);
      end
    else
      begin
        If InterlockedDecrement(PWSOCommonSharedData(fSharedData)^.RefCount) <= 0 then
          FreeMem(fSharedData,WSO_CPLX_SHARED_ITEMSIZE);
      end;
    fSharedData := nil;
  end;
end;

{-------------------------------------------------------------------------------
    TComplexWinSyncObject - public methods
-------------------------------------------------------------------------------}

constructor TComplexWinSyncObject.Create(SecurityAttributes: PSecurityAttributes; const Name: String);
begin
inherited Create;
If RectifyAndSetName(Name) then
  begin
    // process-shared...
    CreateSharedDataLock(SecurityAttributes);
    AllocateSharedData;
    CreateLocks(SecurityAttributes);
  end
else
  begin
    // thread-shared...
    CreateSharedDataLock(SecurityAttributes);
    AllocateSharedData;
    CreateLocks(SecurityAttributes);
  end;
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TComplexWinSyncObject.Create(const Name: String);
begin
Create(nil,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TComplexWinSyncObject.Create;
begin
Create(nil,'');
end;

//------------------------------------------------------------------------------

constructor TComplexWinSyncObject.Open(DesiredAccess: DWORD; InheritHandle: Boolean; const Name: String);
begin
inherited Create;
If RectifyAndSetName(Name) then
  begin
    OpenSharedDataLock(DesiredAccess,InheritHandle);
    AllocateSharedData;
    OpenLocks(DesiredAccess,InheritHandle);
  end
else raise EWSOOpenError.Create('TComplexWinSyncObject.Open: Cannot open unnamed object.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TComplexWinSyncObject.Open(const Name: String{$IFNDEF FPC}; Dummy: Integer = 0{$ENDIF});
begin
Open(SYNCHRONIZE,False,Name);
end;

//------------------------------------------------------------------------------

constructor TComplexWinSyncObject.DuplicateFrom(SourceObject: TComplexWinSyncObject);
begin
inherited Create;
If SourceObject is Self.ClassType then
  begin
    If not SourceObject.ProcessShared then
      begin
        fProcessShared := False;
        {
          Increase reference counter. If it is above 1, all is good and
          continue.
          But if it is below or equal to 1, it means the source was probably
          (being) destroyed - raise an exception.
        }
        If InterlockedIncrement(PWSOCommonSharedData(SourceObject.fSharedData)^.RefCount) > 1 then
          begin
            fSharedDataLock.ThreadSharedLock := SourceObject.fSharedDataLock.ThreadSharedLock;
            fSharedDataLock.ThreadSharedLock.Acquire;
            fSharedData := SourceObject.fSharedData;
            DuplicateLocks(SourceObject);
          end
        else raise EWSOInvalidObject.Create('TComplexWinSyncObject.DuplicateFrom: Source object is in an inconsistent state.');
      end
    else Open(SourceObject.Name);
  end
else raise EWSOInvalidObject.CreateFmt('TComplexWinSyncObject.DuplicateFrom: Incompatible source object (%s).',[SourceObject.ClassName]);
end;

//------------------------------------------------------------------------------

destructor TComplexWinSyncObject.Destroy;
begin
DestroyLocks;
FreeSharedData;
DestroySharedDataLock;
inherited;
end;


{===============================================================================
--------------------------------------------------------------------------------
                               TConditionVariable
--------------------------------------------------------------------------------
===============================================================================}
const
  WSO_COND_SUFFIX_CONDLOCK  = '@cnd_clk';
  WSO_COND_SUFFIX_WAITLOCK  = '@cnd_wlk';
  WSO_COND_SUFFIX_BDONELOCK = '@cnd_blk';
  WSO_COND_SUFFIX_DATALOCK  = '@cnd_dlk';

{===============================================================================
    TConditionVariable - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TConditionVariable - protected methods
-------------------------------------------------------------------------------}

class Function TConditionVariable.GetSharedDataLockSuffix: String;
begin
Result := WSO_COND_SUFFIX_CONDLOCK;
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.AllocateSharedData;
begin
inherited;
fCondSharedData := PWSOCondSharedData(fSharedData);
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.FreeSharedData;
begin
fCondSharedData := nil;
inherited;
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.CreateLocks(SecurityAttributes: PSecurityAttributes);
begin
If fProcessShared then
  begin
  {
    $7FFFFFFF is maximum for semaphores in Windows, anything higher will cause
    invalid parameter error.

    But seriously, if you manage to enter waiting in more than two billion
    threads, you are doing something wrong... or stop using this ancient
    heretical code on Windows 40K, God Emperor of Mankind does not approve!
  }
    CheckAndSetHandle(fWaitLock,
      CreateSemaphoreW(SecurityAttributes,0,DWORD($7FFFFFFF),PWideChar(StrToWide(fName + WSO_COND_SUFFIX_WAITLOCK))));
    CheckAndSetHandle(fBroadcastDoneLock,
      CreateEventW(SecurityAttributes,False,False,PWideChar(StrToWide(fName + WSO_COND_SUFFIX_BDONELOCK))));
  end
else
  begin
    CheckAndSetHandle(fWaitLock,CreateSemaphoreW(SecurityAttributes,0,DWORD($7FFFFFFF),nil));
    CheckAndSetHandle(fBroadcastDoneLock,CreateEventW(SecurityAttributes,False,False,nil));
  end;
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.OpenLocks(DesiredAccess: DWORD; InheritHandle: Boolean);
begin
CheckAndSetHandle(fWaitLock,
  OpenSemaphoreW(DesiredAccess or SEMAPHORE_MODIFY_STATE,InheritHandle,PWideChar(StrToWide(fName + WSO_COND_SUFFIX_WAITLOCK))));
CheckAndSetHandle(fBroadcastDoneLock,
  OpenEventW(DesiredAccess or EVENT_MODIFY_STATE,InheritHandle,PWideChar(StrToWide(fName + WSO_COND_SUFFIX_BDONELOCK))));
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.DuplicateLocks(SourceObject: TComplexWinSyncObject);
begin
fCondSharedData := PWSOCondSharedData(fSharedData);
DuplicateAndSetHandle(fWaitLock,TConditionVariable(SourceObject).fWaitLock);
DuplicateAndSetHandle(fBroadcastDoneLock,TConditionVariable(SourceObject).fBroadcastDoneLock);
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.DestroyLocks;
begin
CloseHandle(fBroadcastDoneLock);
CloseHandle(fWaitLock);
end;

//------------------------------------------------------------------------------

Function TConditionVariable.DoOnPredicateCheck: Boolean;
begin
Result := False;
If Assigned(fOnPredicateCheckEvent) then
  fOnPredicateCheckEvent(Self,Result);
If Assigned(fOnPredicateCheckCallback) then
  fOnPredicateCheckCallback(Self,Result);
end;

//------------------------------------------------------------------------------

Function TConditionVariable.DoOnDataAccess: TWSOWakeOptions;
begin
Result := [];
If Assigned(fOnDataAccessEvent) then
  fOnDataAccessEvent(Self,Result);
If Assigned(fOnDataAccessCallback) then
  fOnDataAccessCallback(Self,Result);
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.SelectWake(WakeOptions: TWSOWakeOptions);
begin
If ([woWakeOne,woWakeAll] *{intersection} WakeOptions) <> [] then
  begin
    If woWakeAll in WakeOptions then
      WakeAll
    else
      Wake;
  end;
end;

{-------------------------------------------------------------------------------
    TConditionVariable - public methods
-------------------------------------------------------------------------------}

procedure TConditionVariable.Sleep(DataLock: THandle; Timeout: DWORD = INFINITE; Alertable: Boolean = False);

  Function InternalWait(IsFirstWait: Boolean): Boolean;
  var
    WaitResult: DWORD;
  begin
    If IsFirstWait then
      WaitResult := SignalObjectAndWait(DataLock,fWaitLock,Timeout,Alertable)
    else
      WaitResult := WaitForSingleObjectEx(fWaitLock,Timeout,Alertable);
    // note that we are waiting on semaphore, so abandoned is not a good result  
    Result := WaitResult = WAIT_OBJECT_0{signaled};
    If WaitResult = WAIT_FAILED then
      raise EWSOWaitError.CreateFmt('TConditionVariable.Sleep.InternalWait: Sleep failed (0x%.8x)',[GetLastError]);
  end;

var
  FirstWait:  Boolean;
  ExitWait:   Boolean;
begin
LockSharedData;
try
  Inc(fCondSharedData^.WaitCount);
finally
  UnlockSharedData;
end;
FirstWait := True;
ExitWait := False;
repeat
  If InternalWait(FirstWait) then
    begin
      LockSharedData;
      try
        If fCondSharedData^.WakeCount > 0 then
          begin
            Dec(fCondSharedData^.WakeCount);
            If (fCondSharedData^.WakeCount <= 0) and fCondSharedData^.Broadcasting then
              begin
                fCondSharedData^.WakeCount := 0;
                fCondSharedData^.Broadcasting := False;
                SetEvent(fBroadcastDoneLock);
              end;
            ExitWait := True; // normal wakeup               
          end;
        // if the WakeCount was 0, then re-enter waiting   
      finally
        UnlockSharedData;
      end;
    end
  else ExitWait := True;  // timeout or spurious wakeup (eg. APC)
  FirstWait := False;     // in case the cycle repeats and re-enters waiting (so the DataLock is not signaled again)
until ExitWait;
// lock the DataLock synchronizer
If not WaitForSingleObject(DataLock,INFINITE) in [WAIT_OBJECT_0,WAIT_ABANDONED] then
  raise EWSOWaitError.Create('TConditionVariable.Sleep: Failed to lock data synchronizer.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

procedure TConditionVariable.Sleep(DataLock: TSimpleWinSyncObject; Timeout: DWORD = INFINITE; Alertable: Boolean = False);
begin
If (DataLock is TEvent) or (DataLock is TMutex) or (DataLock is TSemaphore) then
  Sleep(DataLock.Handle,Timeout,Alertable)
else
  raise EWSOUnsupportedObject.CreateFmt('TConditionVariable.Sleep: Unsupported data synchronizer object type (%s),',[DataLock.ClassName]);
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.Wake;
var
  Waiters:  UInt32;
begin
LockSharedData;
try
  Waiters := fCondSharedData^.WaitCount;
  If Waiters > 0 then
    begin
      Dec(fCondSharedData^.WaitCount);
      Inc(fCondSharedData^.WakeCount);
    end;
finally
  UnlockSharedData;
end;
If Waiters > 0 then
  ReleaseSemaphore(fWaitLock,1,nil);
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.WakeAll;
var
  Waiters:  UInt32;
begin
LockSharedData;
try
  Waiters := fCondSharedData^.WaitCount;
  If Waiters > 0 then
    begin
      Dec(fCondSharedData^.WaitCount,Waiters);
      Inc(fCondSharedData^.WakeCount,Waiters);
      fCondSharedData^.Broadcasting := True;
    end;
finally
  UnlockSharedData;
end;  
If Waiters > 0 then
  begin
    ReleaseSemaphore(fWaitLock,Waiters,nil);
    If WaitForSingleObject(fBroadcastDoneLock,INFINITE) <> WAIT_OBJECT_0 then
      raise EWSOWaitError.Create('TConditionVariable.WakeAll: Wait for broadcast failed.');
  end;
end;

//------------------------------------------------------------------------------

procedure TConditionVariable.AutoCycle(DataLock: THandle);
var
  WakeOptions:  TWSOWakeOptions;
begin
If Assigned(fOnPredicateCheckEvent) or Assigned(fOnPredicateCheckEvent) then
  begin
    // lock synchronizer
    If WaitForSingleObject(DataLock,INFINITE) in [WAIT_OBJECT_0,WAIT_ABANDONED] then
      begin
        // test predicate and wait condition
        while not DoOnPredicateCheck do
          Sleep(DataLock,INFINITE);
        // access protected data
        WakeOptions := DoOnDataAccess;
        // wake waiters before unlock
        If (woWakeBeforeUnlock in WakeOptions) then
          SelectWake(WakeOptions);
        // unlock synchronizer
        If not ReleaseMutex(DataLock) then
          raise EWSOAutoCycleError.CreateFmt('TConditionVariable.AutoCycle: Failed to unlock data synchronizer (0x%.8x).',[GetLastError]);
        // wake waiters after unlock
        If not(woWakeBeforeUnlock in WakeOptions) then
          SelectWake(WakeOptions);
      end
    else raise EWSOAutoCycleError.Create('TConditionVariable.AutoCycle: Failed to lock data synchronizer.');
  end;
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

procedure TConditionVariable.AutoCycle(DataLock: TSimpleWinSyncObject);
var
  WakeOptions:    TWSOWakeOptions;
  ReleaseResult:  Boolean;
begin
If Assigned(fOnPredicateCheckEvent) or Assigned(fOnPredicateCheckCallback) then
  begin
    If (DataLock is TEvent) or (DataLock is TMutex) or (DataLock is TSemaphore) then
      begin
        // lock synchronizer
        If DataLock.WaitFor(INFINITE,False) in [wrSignaled,wrAbandoned] then
          begin
            // test predicate and wait condition
            while not DoOnPredicateCheck do
              Sleep(DataLock,INFINITE);
            // access protected data
            WakeOptions := DoOnDataAccess;
            // wake waiters before unlock
            If (woWakeBeforeUnlock in WakeOptions) then
              SelectWake(WakeOptions);
            // unlock synchronizer
            If DataLock is TEvent then
              ReleaseResult := TEvent(DataLock).SetEvent
            else If DataLock is TMutex then
              ReleaseResult := TMutex(DataLock).ReleaseMutex
            else
              ReleaseResult := TSemaphore(DataLock).ReleaseSemaphore;
            If not ReleaseResult then
              raise EWSOAutoCycleError.CreateFmt('TConditionVariable.AutoCycle: ' +
                                                 'Failed to unlock data synchronizer (0x%.8x).',[DataLock.LastError]);
            // wake waiters after unlock
            If not(woWakeBeforeUnlock in WakeOptions) then
              SelectWake(WakeOptions);
          end
        else raise EWSOAutoCycleError.Create('TConditionVariable.AutoCycle: Failed to lock data synchronizer.');
      end
    else raise EWSOUnsupportedObject.CreateFmt('TConditionVariable.AutoCycle: ' +
                                               'Unsupported data synchronizer object type (%s),',[DataLock.ClassName]);
  end;
end;


{===============================================================================
--------------------------------------------------------------------------------
                              TConditionVariableEx
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TConditionVariableEx - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TConditionVariableEx - public methods
-------------------------------------------------------------------------------}

procedure TConditionVariableEx.CreateLocks(SecurityAttributes: PSecurityAttributes);
begin
inherited CreateLocks(SecurityAttributes);
If fProcessShared then
  CheckAndSetHandle(fDataLock,CreateMutexW(SecurityAttributes,RectBool(False),PWideChar(StrToWide(fName + WSO_COND_SUFFIX_DATALOCK))))
else
  CheckAndSetHandle(fDataLock,CreateMutexW(SecurityAttributes,RectBool(False),nil));
end;

//------------------------------------------------------------------------------

procedure TConditionVariableEx.OpenLocks(DesiredAccess: DWORD; InheritHandle: Boolean);
begin
inherited OpenLocks(DesiredAccess,InheritHandle);
CheckAndSetHandle(fDataLock,
  OpenMutexW(DesiredAccess or MUTEX_MODIFY_STATE,InheritHandle,PWideChar(StrToWide(fName + WSO_COND_SUFFIX_DATALOCK))));
end;

//------------------------------------------------------------------------------

procedure TConditionVariableEx.DuplicateLocks(SourceObject: TComplexWinSyncObject);
begin
inherited DuplicateLocks(SourceObject);
DuplicateAndSetHandle(fDataLock,TConditionVariableEx(SourceObject).fDataLock);
end;

//------------------------------------------------------------------------------

procedure TConditionVariableEx.DestroyLocks;
begin
inherited;
CloseHandle(fDataLock);
end;

{-------------------------------------------------------------------------------
    TConditionVariableEx - public methods
-------------------------------------------------------------------------------}

procedure TConditionVariableEx.Lock;
begin
If not WaitForSingleObject(fDataLock,INFINITE) in [WAIT_OBJECT_0,WAIT_ABANDONED] then
  raise EWSOWaitError.Create('TConditionVariableEx.Lock: Failed to lock data synchronizer.');
end;

//------------------------------------------------------------------------------

procedure TConditionVariableEx.Unlock;
begin
If not ReleaseMutex(fDataLock) then
  raise EWSOWaitError.CreateFmt('TConditionVariableEx.Lock: Failed to unlock data synchronizer (0x%.8x).',[GetLastError]);
end;

//------------------------------------------------------------------------------

procedure TConditionVariableEx.Sleep(Timeout: DWORD = INFINITE; Alertable: Boolean = False);
begin
Sleep(fDataLock,Timeout,Alertable);
end;

//------------------------------------------------------------------------------

procedure TConditionVariableEx.AutoCycle;
begin
AutoCycle(fDataLock);
end;


{===============================================================================
--------------------------------------------------------------------------------
                                    TBarrier
--------------------------------------------------------------------------------
===============================================================================}
const
  WSO_BARR_SUFFIX_BARRLOCK  = '@brr_blk';
  WSO_BARR_SUFFIX_RELLOCK   = '@brr_rlk';
  WSO_BARR_SUFFIX_WAITLOCK  = '@brr_wlk';

{===============================================================================
    TBarrier - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TBarrier - protected methods
-------------------------------------------------------------------------------}

Function TBarrier.GetCount: Integer;
begin
Result := fBarrierSharedData^.MaxWaitCount;
end;

//------------------------------------------------------------------------------

class Function TBarrier.GetSharedDataLockSuffix: String;
begin
Result := WSO_BARR_SUFFIX_BARRLOCK;
end;

//------------------------------------------------------------------------------

procedure TBarrier.AllocateSharedData;
begin
inherited;
fBarrierSharedData := PWSOBarrierSharedData(fSharedData);
end;

//------------------------------------------------------------------------------

procedure TBarrier.FreeSharedData;
begin
fBarrierSharedData := nil;
inherited;
end;

//------------------------------------------------------------------------------

procedure TBarrier.CreateLocks(SecurityAttributes: PSecurityAttributes);
begin
If fProcessShared then
  begin
    CheckAndSetHandle(fReleaseLock,
      CreateEventW(SecurityAttributes,True,False,PWideChar(StrToWide(fName + WSO_BARR_SUFFIX_RELLOCK))));
    CheckAndSetHandle(fWaitLock,
      CreateEventW(SecurityAttributes,True,False,PWideChar(StrToWide(fName + WSO_BARR_SUFFIX_WAITLOCK))));
  end
else
  begin
    CheckAndSetHandle(fReleaseLock,CreateEventW(SecurityAttributes,True,False,nil));
    CheckAndSetHandle(fWaitLock,CreateEventW(SecurityAttributes,True,False,nil));
  end;
end;

//------------------------------------------------------------------------------

procedure TBarrier.OpenLocks(DesiredAccess: DWORD; InheritHandle: Boolean);
begin
CheckAndSetHandle(fReleaseLock,
  OpenEventW(DesiredAccess or EVENT_MODIFY_STATE,InheritHandle,PWideChar(StrToWide(fName + WSO_BARR_SUFFIX_RELLOCK))));
CheckAndSetHandle(fWaitLock,
  OpenEventW(DesiredAccess or EVENT_MODIFY_STATE,InheritHandle,PWideChar(StrToWide(fName + WSO_BARR_SUFFIX_WAITLOCK))));
end;

//------------------------------------------------------------------------------

procedure TBarrier.DuplicateLocks(SourceObject: TComplexWinSyncObject);
begin
fBarrierSharedData := PWSOBarrierSharedData(fSharedData);
DuplicateAndSetHandle(fReleaseLock,TBarrier(SourceObject).fReleaseLock);
DuplicateAndSetHandle(fWaitLock,TBarrier(SourceObject).fWaitLock);
end;

//------------------------------------------------------------------------------

procedure TBarrier.DestroyLocks;
begin
CloseHandle(fWaitLock);
CloseHandle(fReleaseLock);
end;

{-------------------------------------------------------------------------------
    TBarrier - public methods
-------------------------------------------------------------------------------}

constructor TBarrier.Create(SecurityAttributes: PSecurityAttributes; const Name: String);
begin
{
  Barrier with count of 1 is seriously pointless, but if you call a constructor
  without specifying the count, what do you expect to happen?!
}
Create(SecurityAttributes,1,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBarrier.Create(const Name: String);
begin
Create(nil,1,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBarrier.Create;
begin
Create(nil,1,'');
end;


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBarrier.Create(SecurityAttributes: PSecurityAttributes; Count: Integer; const Name: String);
begin
inherited Create(SecurityAttributes,Name);
If Count > 0 then
  begin
    If fBarrierSharedData^.MaxWaitCount = 0 then
      fBarrierSharedData^.MaxWaitCount := Count;
  end
else raise EWSOInvalidValue.CreateFmt('TBarrier.Create: Invalid count (%d)',[Count]);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBarrier.Create(Count: Integer; const Name: String);
begin
Create(nil,Count,Name);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBarrier.Create(Count: Integer);
begin
Create(nil,Count,'');
end;

//------------------------------------------------------------------------------

Function TBarrier.Wait: Boolean;
var
  ExitWait: Boolean;
begin
Result := False;
repeat
  LockSharedData;
  If fBarrierSharedData^.Releasing then
    begin
    {
      Releasing is in progress, so this thread cannot queue on the barrier.
      Unlock shared data and wait for fReleaseLock to become signaled, which
      happens at the end of releasing.
    }
      UnlockSharedData;
      If WaitForSingleObject(fReleaseLock,INFINITE) <> WAIT_OBJECT_0 then
        raise EWSOWaitError.Create('TBarrier.Wait: Failed waiting on release lock.');
      ExitWait := False;
      // Releasing should be done by this point. Re-enter waiting.
    end
  else
    begin
      // Releasing is currently not running.
      Inc(fBarrierSharedData^.WaitCount);
      If fBarrierSharedData^.WaitCount >= fBarrierSharedData^.MaxWaitCount then
        begin
        {
          Maximum number of waiting threads for this barrier has been reached.

          First prevent other threads from queueing on this barrier by
          resetting fReleaseLock and indicating the fact in shared data.
        }
          ResetEvent(fReleaseLock);
          fBarrierSharedData^.Releasing := True;
          Dec(fBarrierSharedData^.WaitCount); // remove self from waiting count
        {
          Now unlock shared data and release all waiting threads from
          fWaitLock.

          Unlocking shared data at this point is secure because any thread that
          will acquire them will encounter Releasing field to be true and will
          therefore enter waiting on fReleaseLock, which is now non-signaled.
        }          
          UnlockSharedData;
          SetEvent(fWaitLock);
          Result := True; // indicate we have released the barrier
        end
      else
        begin
        {
          Maximum number of waiters not reached.

          Just unlock the shared data and enter waiting on fWaitLock.
        }
          UnlockSharedData;
          If WaitForSingleObject(fWaitLock,INFINITE) <> WAIT_OBJECT_0 then
            raise EWSOWaitError.Create('TBarrier.Wait: Failed waiting on the barrier.');
        {
          The wait lock has been set to signaled, so the barrier is releasing.

          Remove self from waiting threads count and, if we are last to be
          released, stop releasing and signal end of releasing to threads
          waiting on fReleaseLock and also mark it in shared data.
        }
          LockSharedData;
          try
            Dec(fBarrierSharedData^.WaitCount);
            If fBarrierSharedData^.WaitCount <= 0 then
              begin
                fBarrierSharedData^.WaitCount := 0;
                fBarrierSharedData^.Releasing := False;
                ResetEvent(fWaitLock);
                SetEvent(fReleaseLock);
              end;
          finally
            UnlockSharedData;
          end;
        end;
      ExitWait := True;
    end;
until ExitWait;
end;

//------------------------------------------------------------------------------

Function TBarrier.Release: Integer;
var
  SetWaitLock:  Boolean;
begin
SetWaitLock := False;
LockSharedData;
try
  If not fBarrierSharedData^.Releasing then
    begin
      If fBarrierSharedData^.WaitCount > 0 then
        begin
          SetWaitLock := True;
          Result := fBarrierSharedData^.WaitCount;
          ResetEvent(fReleaseLock);
          fBarrierSharedData^.Releasing := True;
        end
      else Result := 0;
    end
  else Result := -1;
finally
  UnlockSharedData;
end;
If SetWaitLock then
  SetEvent(fWaitLock);
end;


{===============================================================================
--------------------------------------------------------------------------------
                                 TReadWriteLock
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TReadWriteLock - thread-local data
===============================================================================}
threadvar
  WSO_TLSVAR_RWL_ReadLockCount:   UInt32;   // initialized to 0
  WSO_TLSVAR_RWL_HoldsWriteLock:  Boolean;  // initialized to false

{===============================================================================
    TReadWriteLock - class implementation
===============================================================================}



{===============================================================================
--------------------------------------------------------------------------------
                                 Wait functions
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Wait functions - implementation constants
===============================================================================}
const
  MWMO_WAITALL        = DWORD($00000001);
  MWMO_ALERTABLE      = DWORD($00000002);
  MWMO_INPUTAVAILABLE = DWORD($00000004);

const
  MAXIMUM_WAIT_OBJECTS = 3; {$message 'debug'}

{===============================================================================
    Wait functions - internal functions
===============================================================================}

Function MaxWaitObjCount(MsgWaitOptions: TMessageWaitOptions): Integer;
begin
If mwoEnable in MsgWaitOptions then
  Result := MAXIMUM_WAIT_OBJECTS - 1
else
  Result := MAXIMUM_WAIT_OBJECTS;
end;

{===============================================================================
--------------------------------------------------------------------------------
                            Wait functions (N <= MAX)
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Wait functions (N <= MAX) - internal functions
===============================================================================}

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
        If not(mwoEnable in MsgWaitOptions) or (Integer(WaitResult - WAIT_ABANDONED_0) < Count) then
          begin
            Result := wrAbandoned;
            If not WaitAll then
              Index := Integer(WaitResult - WAIT_ABANDONED_0);
          end
        else Result := wrError;
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

Function WaitForMultipleObjects_Internal(Objects: array of TSimpleWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
var
  Handles:  array of THandle;
  i:        Integer;
begin
If Length(Objects) > 0 then
  begin
    SetLength(Handles,Length(Objects));
    For i := Low(Objects) to High(Objects) do
      Handles[i] := Objects[i].Handle;
    Result := WaitForMultipleHandles_Sys(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
  end
else raise EWSOMultiWaitInvalidCount.CreateFmt('WaitForMultipleObjects_Internal: Invalid object count (%d).',[Length(Objects)]);
end;

{===============================================================================
    Wait functions (N <= MAX) - public functions
===============================================================================}

Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
begin
Result := WaitForMultipleHandles_Sys(Handles,Count,WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult;
begin
Result := WaitForMultipleHandles_Sys(Handles,Count,WaitAll,Timeout,Index,Alertable,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForMultipleHandles_Sys(Handles,Count,WaitAll,Timeout,Index,Alertable,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForMultipleHandles_Sys(Handles,Count,WaitAll,INFINITE,Index,False,[],0);
end;

//------------------------------------------------------------------------------

Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
begin
If Length(Handles) > 0 then
  Result := WaitForMultipleHandles_Sys(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask)
else
  raise EWSOMultiWaitInvalidCount.Create('WaitForMultipleHandles: Empty handle array.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult;
begin
If Length(Handles) > 0 then
  Result := WaitForMultipleHandles_Sys(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,Timeout,Index,Alertable,[],0)
else
  raise EWSOMultiWaitInvalidCount.Create('WaitForMultipleHandles: Empty handle array.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult;
var
  Index:  Integer;
begin
If Length(Handles) > 0 then
  Result := WaitForMultipleHandles_Sys(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,Timeout,Index,Alertable,[],0)
else
  raise EWSOMultiWaitInvalidCount.Create('WaitForMultipleHandles: Empty handle array.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleHandles(Handles: array of THandle; WaitAll: Boolean): TWaitResult;
var
  Index:  Integer;
begin
If Length(Handles) > 0 then
  Result := WaitForMultipleHandles_Sys(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,INFINITE,Index,False,[],0)
else
  raise EWSOMultiWaitInvalidCount.Create('WaitForMultipleHandles: Empty handle array.');
end;

//------------------------------------------------------------------------------

Function WaitForMultipleObjects(Objects: array of TSimpleWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
begin
Result := WaitForMultipleObjects_Internal(Objects,WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TSimpleWinSyncObject; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult;
begin
Result := WaitForMultipleObjects_Internal(Objects,WaitAll,Timeout,Index,Alertable,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TSimpleWinSyncObject; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForMultipleObjects_Internal(Objects,WaitAll,Timeout,Index,Alertable,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForMultipleObjects(Objects: array of TSimpleWinSyncObject; WaitAll: Boolean): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForMultipleObjects_Internal(Objects,WaitAll,INFINITE,Index,False,[],0);
end;


{===============================================================================
--------------------------------------------------------------------------------
                            Wait functions (N > MAX)
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Wait functions (N > MAX) - implementation types
===============================================================================}
{
  invoker_thread - level --- stage_0 - wait_thread - group
                          |- stage_1 - wait_thread - group
                         ...
                          |- stage_n - wait_thread - group
                          |- stage_m - wait_thread - level --- stage_0 - wait_thread - group
                                                            |- stage_1 - wait_thread - group
                                                           ...
                                                            |- stage_n - wait_thread - group
}
{$message '^^rework^^'}

type
  TWSOWaitParams = record
    WaitAll:        Boolean;
    Timeout:        DWORD;
    Alertable:      Boolean;
    MsgWaitOptions: TMessageWaitOptions;
    WakeMask:       DWORD;
  end;

  TWSOWaitGroupHandles = array[0..Pred(MAXIMUM_WAIT_OBJECTS)] of THandle;

  TWSOWaitGroup = record
    Handles:    TWSOWaitGroupHandles;
    HandlesPtr: PHandle;
    Count:      Integer;      // must be strictly above zero
    IndexBase:  Integer;      // index of the first item in the original array
    // group wait result
    WaitResult: TWaitResult;  // init to wrFatal
    Index:      Integer;      // init to -1
  end;

  TWSOWaitLevel = record
    WaitGroups: array of TWSOWaitGroup;
    // level wait result
    WaitResult: TWaitResult;  // init to wrFatal
    Index:      Integer;      // init to -1
  end;

  TWSOWaitInternals = record
  {
    ReadyCounter is initally set to a number of all waits within the tree
    (including waits for waiter threads). It is atomically decremented before
    each wait. When it is above zero after the decrement, enter waiting on
    ReadyEvent. When it reaches zero, waiting is not entered and, instead,
    the ReadyEvent is set (to signaled), which will release all waiting threads
    at once and they will then enter the main waiting.

    Note that this is done only when waiting for one object. It is pointless
    in waiting for all objects.
  }
    ReadyCounter:   Integer;
    ReadyEvent:     THandle;
    DoneCounter:    Integer;
    DoneEvent:      THandle;
    ReleaserEvent:  THandle;
    FirstDone:      UInt64; // higher 32bits for level index, lower for group index
  end;

  TWSOWaitArgs = record
    WaitParams:     TWSOWaitParams;  
    WaitLevels:     array of TWSOWaitLevel;
    WaitInternals:  TWSOWaitInternals;
  end;   
  PWSOWaitArgs = ^TWSOWaitArgs;

{===============================================================================
    Wait functions (N > MAX) - TWSOWaiterThread class declaration
===============================================================================}
type
  TWSOWaiterThread = class(TThread)
  protected
    fFreeMark:        Integer;
    fWaitArgs:        PWSOWaitArgs;
    procedure Execute; override;
  public
    constructor Create(WaitArgs: PWSOWaitArgs);
    Function MarkForAutoFree: Boolean; virtual;
  end;

{===============================================================================
    Wait functions (N > MAX) - TWSOWaiterThread class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    Wait functions (N > MAX) - TWSOWaiterThread protected methods
-------------------------------------------------------------------------------}

procedure TWSOWaiterThread.Execute;
begin
If InterlockedExchange(fFreeMark,-1) <> 0 then
  FreeOnTerminate := True;
end;

{-------------------------------------------------------------------------------
    Wait functions (N > MAX) - TWSOWaiterThread public methods
-------------------------------------------------------------------------------}

constructor TWSOWaiterThread.Create(WaitArgs: PWSOWaitArgs);
begin
inherited Create(False);
FreeOnTerminate := False;
InterlockedStore(fFreeMark,0);
fWaitArgs := WaitArgs;
end;

//------------------------------------------------------------------------------

Function TWSOWaiterThread.MarkForAutoFree: Boolean;
begin
Result := InterlockedExchange(fFreeMark,-1) = 0;
end;

{===============================================================================
    Wait functions (N > MAX) - TWSOGroupWaiterThread class declaration
===============================================================================}
type
  TWSOGroupWaiterThread = class(TWSOWaiterThread)
  protected
    fWaitLevelIndex:  Integer;
    fWaitGroupIndex:  Integer;
    procedure Execute; override;
  public
    constructor Create(WaitArgs: PWSOWaitArgs; WaitLevelIndex, WaitGroupIndex: Integer);
  end;

{===============================================================================
    Wait functions (N > MAX) - TWSOGroupWaiterThread class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    Wait functions (N > MAX) - TWSOGroupWaiterThread protected methods
-------------------------------------------------------------------------------}

procedure TWSOGroupWaiterThread.Execute;
begin
try
  If InterlockedDecrement(fWaitArgs^.WaitInternals.ReadyCounter) > 0 then
    begin
      If WaitForSingleObject(fWaitArgs^.WaitInternals.ReadyEvent,INFINITE) <> WAIT_OBJECT_0 then
        raise EWSoWaitError.Create('TWSOGroupWaiterThread.Execute: Failed to wait on ready event.');
    end
  else SetEvent(fWaitArgs^.WaitInternals.ReadyEvent);
{
  No alertable or message waiting is allowed here, therefore do not pass those
  arguments to final wait (alertable and message waits are observed only in
  the first level wait, as it is executed by the invoking thread).
}
  with fWaitArgs^.WaitParams, fWaitArgs^.WaitLevels[fWaitLevelIndex].WaitGroups[fWaitGroupIndex] do
    WaitResult := WaitForMultipleHandles_Sys(HandlesPtr,Count,WaitAll,Timeout,Index,False,[],0);
  // if the FirstDone is still in its initial state (-1), assign indices of this group and level
  InterlockedCompareExchange(fWaitArgs^.WaitInternals.FirstDone,UInt64Get(fWaitLevelIndex,fWaitGroupIndex),UInt64(-1));
  // if waiting for one object, signal other waits that we already got the "winner"
  If not fWaitArgs^.WaitParams.WaitAll then
    SetEvent(fWaitArgs^.WaitInternals.ReleaserEvent);
except
  // eat-up all exceptions, so they will not kill the thread
  fWaitArgs^.WaitLevels[fWaitLevelIndex].WaitGroups[fWaitGroupIndex].WaitResult := wrFatal;
  fWaitArgs^.WaitLevels[fWaitLevelIndex].WaitGroups[fWaitGroupIndex].Index := -1;
end;
{
  Following must be here, not sooner, to ensure the fWaitArgs is not accessed
  after the invoking thread ends its wait and frees it.
}
If InterlockedDecrement(fWaitArgs^.WaitInternals.DoneCounter) <= 0 then
  SetEvent(fWaitArgs^.WaitInternals.DoneEvent);
inherited;
end;

{-------------------------------------------------------------------------------
    Wait functions (N > MAX) - TWSOGroupWaiterThread public methods
-------------------------------------------------------------------------------}

constructor TWSOGroupWaiterThread.Create(WaitArgs: PWSOWaitArgs; WaitLevelIndex, WaitGroupIndex: Integer);
begin
inherited Create(WaitArgs);
fWaitLevelIndex := WaitLevelIndex;
fWaitGroupIndex := WaitGroupIndex;
end;

{===============================================================================
    Wait functions (N > MAX) - TWSOLevelWaiterThread class declaration
===============================================================================}
type
  TWSOLevelWaiterThread = class(TWSOWaiterThread)
  protected
    fWaitLevelIndex:  Integer;
    procedure Execute; override;
  public
    constructor Create(WaitArgs: PWSOWaitArgs; WaitLevelIndex: Integer);
  end;

{===============================================================================
    Wait functions (N > MAX) - TWSOLevelWaiterThread class implementation
===============================================================================}

procedure WaitForManyHandles_All(WaitArgs: PWSOWaitArgs; WaitLevelIndex: Integer); forward;
procedure WaitForManyHandles_One(WaitArgs: PWSOWaitArgs; WaitLevelIndex: Integer); forward;

{-------------------------------------------------------------------------------
    Wait functions (N > MAX) - TWSOLevelWaiterThread protected methods
-------------------------------------------------------------------------------}

procedure TWSOLevelWaiterThread.Execute;
begin
// exception catching is part of called functions
If fWaitArgs^.WaitParams.WaitAll then
  WaitForManyHandles_All(fWaitArgs,fWaitLevelIndex)
else
  WaitForManyHandles_One(fWaitArgs,fWaitLevelIndex);
inherited;
end;

{-------------------------------------------------------------------------------
    Wait functions (N > MAX) - TWSOLevelWaiterThread public methods
-------------------------------------------------------------------------------}

constructor TWSOLevelWaiterThread.Create(WaitArgs: PWSOWaitArgs; WaitLevelIndex: Integer);
begin
inherited Create(WaitArgs);
fWaitLevelIndex := WaitLevelIndex;
end;

{===============================================================================
    Wait functions (N > MAX) - internal functions
===============================================================================}

procedure WaitForManyHandles_All(WaitArgs: PWSOWaitArgs; WaitLevelIndex: Integer);
var
  IsFirstLevel:         Boolean;
  IsLastLevel:          Boolean;
  WaiterThreads:        array of TWSOWaiterThread;
  WaiterThreadsHandles: array of THandle;
  i:                    Integer;
begin
try
{
  For each wait group in this level, a waiter thread is spawned. This thread
  will then wait on a portion of handles assigned to that group and we will
  wait on those spawned threads.

  When handles will become signaled or their waiting ends in other ways (error,
  timeout, ...), the waiter threads will end their waiting and become in turn
  signaled too, at which point this function finishes and exits.

  If this is not last level, we also add another thread to be waited on. This
  thread will, instead of wait group, wait on the next level.
}
  IsFirstLevel := WaitLevelIndex <= Low(WaitArgs^.WaitLevels);
  IsLastLevel := WaitLevelIndex >= High(WaitArgs^.WaitLevels);
  // prepare array of waiter threads / wait handles
  If IsLastLevel then
    SetLength(WaiterThreads,Length(WaitArgs^.WaitLevels[WaitLevelIndex].WaitGroups))
  else
    SetLength(WaiterThreads,Length(WaitArgs^.WaitLevels[WaitLevelIndex].WaitGroups) + 1); // + wait on the next level
  SetLength(WaiterThreadsHandles,Length(WaiterThreads));
  // create and fill waiter threads
  For i := Low(WaiterThreads) to High(WaiterThreads) do
    begin
      If not IsLastLevel and (i >= High(WaiterThreads)) then
        WaiterThreads[i] := TWSOLevelWaiterThread.Create(WaitArgs,Succ(WaitLevelIndex))
      else
        WaiterThreads[i] := TWSOGroupWaiterThread.Create(WaitArgs,WaitLevelIndex,i);
    {
      Threads enter their internal waiting immediately.

      Any waiter thread can finish even before its handle is obtained, but the
      handle should still be walid and usable in waiting since no thread is
      freed automatically at this point.
    }
      WaiterThreadsHandles[i] := WaiterThreads[i].Handle;
    end;
{
  Now wait on all waiter threads with no timeout - the timeout is in effect
  for objects we are waiting on, which the waiter threads are not.
}
  If InterlockedDecrement(WaitArgs^.WaitInternals.ReadyCounter) > 0 then
    begin
      If WaitForSingleObject(WaitArgs^.WaitInternals.ReadyEvent,INFINITE) <> WAIT_OBJECT_0 then
        raise EWSoWaitError.Create('WaitForManyHandles_All: Failed to wait on ready event.');
    end
  else SetEvent(WaitArgs^.WaitInternals.ReadyEvent);
  // the waiting itself...
  If IsFirstLevel then
    // first level, use Alertable and Message wait settings
    WaitArgs^.WaitLevels[WaitLevelIndex].WaitResult := WaitForMultipleHandles_Sys(
      Addr(WaiterThreadsHandles[Low(WaiterThreadsHandles)]),
      Length(WaiterThreadsHandles),
      True,INFINITE,
      WaitArgs^.WaitLevels[WaitLevelIndex].Index,
      WaitArgs^.WaitParams.Alertable,
      WaitArgs^.WaitParams.MsgWaitOptions,
      WaitArgs^.WaitParams.WakeMask)
  else
    // second+ level, ignore Alertable and Message wait settings
    WaitArgs^.WaitLevels[WaitLevelIndex].WaitResult := WaitForMultipleHandles_Sys(
      Addr(WaiterThreadsHandles[Low(WaiterThreadsHandles)]),
      Length(WaiterThreadsHandles),
      True,INFINITE,
      WaitArgs^.WaitLevels[WaitLevelIndex].Index,
      False,[],0);
  // process (possibly invalid) result
  case WaitArgs^.WaitLevels[WaitLevelIndex].WaitResult of
    wrSignaled:;    // all is good
    wrAbandoned:    raise EWSOWaitError.Create('WaitForManyHandles_All: Invalid wait result (abandoned).');
    wrIOCompletion: If not IsFirstLevel then
                      raise EWSOWaitError.Create('WaitForManyHandles_All: Alertablee waiting not allowed here.');
    wrMessage:      If not IsFirstLevel then
                      raise EWSOWaitError.Create('WaitForManyHandles_All: Message waiting not allowed here.');
    wrTimeout:      raise EWSOWaitError.Create('WaitForManyHandles_All: Wait timeout not allowed here.');
    wrError:        raise EWSOWaitError.CreateFmt('WaitForManyHandles_All: Wait error (%d).',[GetLastError]);
    wrFatal:        raise EWSOWaitError.Create('WaitForManyHandles_All: Fatal error during waiting.');
  else
   raise EWSOWaitError.Create('WaitForManyHandles_All: Invalid wait result.');
  end;
{
  If the waiting ended with wrSignaled, then all waiter threads have ended by
  this time. But, if waiting ended with other result, then some waiter threads
  might be still waiting.
  We do not need them anymore and forcefull termination is not a good idea at
  this point, so we mark them for automatic freeing at their termination and
  leave them to their fate.

  If thread already finished its waiting (in which case its method
  MarkForAutoFree returns false), then it is freed immediately as it cannot
  free itself anymore.
}
  For i := Low(WaiterThreads) to High(WaiterThreads) do
    If not WaiterThreads[i].MarkForAutoFree then
      begin
        WaiterThreads[i].WaitFor;
        WaiterThreads[i].Free;
      end;
except
  WaitArgs^.WaitLevels[WaitLevelIndex].WaitResult := wrFatal;
  WaitArgs^.WaitLevels[WaitLevelIndex].Index := -1;
end;
If InterlockedDecrement(WaitArgs^.WaitInternals.DoneCounter) <= 0 then
  SetEvent(WaitArgs^.WaitInternals.DoneEvent);
end;

//------------------------------------------------------------------------------

procedure WaitForManyHandles_One(WaitArgs: PWSOWaitArgs; WaitLevelIndex: Integer);
var
  IsFirstLevel:         Boolean;
  IsLastLevel:          Boolean;
  WaiterThreads:        array of TWSOWaiterThread;
  WaiterThreadsHandles: array of THandle;
  i:                    Integer;
begin
try
{
  There is more than MaxWaitObjCount handles to be waited and if any single one
  of them gets signaled, the waiting will end.

  Last handle is expected to be a releaser event.

  We spawn appropriate number of waiter threads and split the handles between
  them. Each thread will, along with its portion of handles, get a handle to
  the releaser.

  When one of the handles get signaled and any waiting ends, the releaser is
  set to signaled. And since every thread has it among its wait handles, they
  all end their waiting and exit.
}
  IsFirstLevel := WaitLevelIndex <= Low(WaitArgs^.WaitLevels);
  IsLastLevel := WaitLevelIndex >= High(WaitArgs^.WaitLevels);
  // prepare array of waiter threads / wait handles
  If IsLastLevel then
    SetLength(WaiterThreads,Length(WaitArgs^.WaitLevels[WaitLevelIndex].WaitGroups))
  else
    SetLength(WaiterThreads,Length(WaitArgs^.WaitLevels[WaitLevelIndex].WaitGroups) + 1); // + wait on the next level
  SetLength(WaiterThreadsHandles,Length(WaiterThreads));
  // create and fill waiter threads
  For i := Low(WaiterThreads) to High(WaiterThreads) do
    begin
      If not IsLastLevel and (i >= High(WaiterThreads)) then
        WaiterThreads[i] := TWSOLevelWaiterThread.Create(WaitArgs,Succ(WaitLevelIndex))
      else
        WaiterThreads[i] := TWSOGroupWaiterThread.Create(WaitArgs,WaitLevelIndex,i);
      WaiterThreadsHandles[i] := WaiterThreads[i].Handle;
    end;
  // waiting...  
  If InterlockedDecrement(WaitArgs^.WaitInternals.ReadyCounter) > 0 then
    begin
      If WaitForSingleObject(WaitArgs^.WaitInternals.ReadyEvent,INFINITE) <> WAIT_OBJECT_0 then
        raise EWSoWaitError.Create('WaitForManyHandles_One: Failed to wait on ready event.');
    end
  else SetEvent(WaitArgs^.WaitInternals.ReadyEvent);
  // the waiting itself...
  If IsFirstLevel then
    // first level, use Alertable and Message wait settings
    WaitArgs^.WaitLevels[WaitLevelIndex].WaitResult := WaitForMultipleHandles_Sys(
      Addr(WaiterThreadsHandles[Low(WaiterThreadsHandles)]),
      Length(WaiterThreadsHandles),
      False,INFINITE,
      WaitArgs^.WaitLevels[WaitLevelIndex].Index,
      WaitArgs^.WaitParams.Alertable,
      WaitArgs^.WaitParams.MsgWaitOptions,
      WaitArgs^.WaitParams.WakeMask)
  else
    // second+ level, ignore Alertable and Message wait settings
    WaitArgs^.WaitLevels[WaitLevelIndex].WaitResult := WaitForMultipleHandles_Sys(
      Addr(WaiterThreadsHandles[Low(WaiterThreadsHandles)]),
      Length(WaiterThreadsHandles),
      False,INFINITE,
      WaitArgs^.WaitLevels[WaitLevelIndex].Index,
      False,[],0);
  // process (possibly invalid) result
  case WaitArgs^.WaitLevels[WaitLevelIndex].WaitResult of
    wrSignaled:;    // all is good
    wrAbandoned:    raise EWSOWaitError.Create('WaitForManyHandles_One: Invalid wait result (abandoned).');
    wrIOCompletion: If not IsFirstLevel then
                      raise EWSOWaitError.Create('WaitForManyHandles_One: Alertablee waiting not allowed here.');
    wrMessage:      If not IsFirstLevel then
                      raise EWSOWaitError.Create('WaitForManyHandles_One: Message waiting not allowed here.');
    wrTimeout:      raise EWSOWaitError.Create('WaitForManyHandles_One: Wait timeout not allowed here.');
    wrError:        raise EWSOWaitError.CreateFmt('WaitForManyHandles_One: Wait error (%d).',[GetLastError]);
    wrFatal:        raise EWSOWaitError.Create('WaitForManyHandles_One: Fatal error during waiting.');
  else
   raise EWSOWaitError.Create('WaitForManyHandles_One: Invalid wait result.');
  end;      
{
  The releaser is set in waiter threads, but in case the waiting for those
  threads itself ended with non-signaled result (error, message, ...), we
  have to set it here too to release all the waitings.

  After that, wait for all waiter threads to finish and free them.
}
  SetEvent(WaitArgs^.WaitInternals.ReleaserEvent);
  For i := Low(WaiterThreads) to High(WaiterThreads) do
    begin
      WaiterThreads[i].WaitFor;
      WaiterThreads[i].Free;
    end;
except
  WaitArgs^.WaitLevels[WaitLevelIndex].WaitResult := wrFatal;
  WaitArgs^.WaitLevels[WaitLevelIndex].Index := -1;
end;
If InterlockedDecrement(WaitArgs^.WaitInternals.DoneCounter) <= 0 then
  SetEvent(WaitArgs^.WaitInternals.DoneEvent);
end;

//------------------------------------------------------------------------------

procedure WaitForManyHandles_Preprocess(var WaitArgs: TWSOWaitArgs; Handles: PHandle; Count: Integer);

  Function WaitGroupHandlesHigh(const HandlesArray: TWSOWaitGroupHandles): Integer;
  begin
    If WaitArgs.WaitParams.WaitAll then
      Result := High(HandlesArray)
    else
      Result := High(HandlesArray) - 1;
  end;

var
  GroupCount:   Integer;
  Cntr:         Integer;
  i,j,k:        Integer;
  LevelGroups:  Integer;
  TempHPtr:     PHandle;
begin
// wait parameters in WaitArgs are expected to be filled
{
  Calculate how many groups will be there.

  Each group can contain MAXIMUM_WAIT_OBJECTS of waited objects if WaitAll is
  true. But if it is false (waiting for one object), each group must also
  contain an releaser event (put at the end of the array).
}
If WaitArgs.WaitParams.WaitAll then
  GroupCount := Ceil(Count / MAXIMUM_WAIT_OBJECTS)
else
  GroupCount := Ceil(Count / Pred(MAXIMUM_WAIT_OBJECTS));
{
  Given the group count, calculate number of levels.

  Each level can wait on MAXIMUM_WAIT_OBJECTS of groups (waiter threads).
  But if there is another level after the current one, the current must also
  wait on that next level.
  If message waiting is enabled, the first level (executed in the context of
  invoker thread) must also wait for messages, which further decreases the
  limit.

    G ... number of groups
    L ... numger of levels
    M ... maximum number of waited objects per level

    Message waiting

      Total number of waited objects in levels will be number of groups plus
      all waits for next levels (in all levels except the last one, so L - 1),
      plus 1 for messages wait in the first level.

              L = (G + (L - 1) + 1) / M
              L = (G + L) / M
             ML = G + L
         ML - L = G
       L(M - 1) = G
              L = G / (M - 1)   <<<

    Non-message waiting

      Total number of waited objects in levels is number of groups plus all
      waits for next levels (L - 1).

                L = (G + (L - 1)) / M
               ML = G + L - 1
           ML - L = G - 1
       L(M   - 1) = G - 1
                L = (G - 1) / (M - 1)   <<<
}
If mwoEnable in WaitArgs.WaitParams.MsgWaitOptions then
  SetLength(WaitArgs.WaitLevels,Ceil(GroupCount / Pred(MAXIMUM_WAIT_OBJECTS)))
else
  SetLength(WaitArgs.WaitLevels,Ceil(Pred(GroupCount) / Pred(MAXIMUM_WAIT_OBJECTS)));
// prepare groups
Cntr := GroupCount;
For i := Low(WaitArgs.WaitLevels) to High(WaitArgs.WaitLevels) do
  begin
    LevelGroups := Min(MAXIMUM_WAIT_OBJECTS,Cntr);
    If i < High(WaitArgs.WaitLevels) then
      Dec(LevelGroups); // wait for next level
    If (mwoEnable in WaitArgs.WaitParams.MsgWaitOptions) and (i <= Low(WaitArgs.WaitLevels)) then
      Dec(LevelGroups); // message wait
    SetLength(WaitArgs.WaitLevels[i].WaitGroups,LevelGroups);
    Dec(Cntr,LevelGroups);
    // init level wait result
    WaitArgs.WaitLevels[i].WaitResult := wrFatal;
    WaitArgs.WaitLevels[i].Index := -1;
  end;
// prepare groups and fill their handle arrays
TempHPtr := Handles;
Cntr := 0;
For i := Low(WaitArgs.WaitLevels) to High(WaitArgs.WaitLevels) do
  For j := Low(WaitArgs.WaitLevels[i].WaitGroups) to High(WaitArgs.WaitLevels[i].WaitGroups) do
    begin
      WaitArgs.WaitLevels[i].WaitGroups[j].HandlesPtr := Addr(WaitArgs.WaitLevels[i].WaitGroups[j].Handles);
      WaitArgs.WaitLevels[i].WaitGroups[j].Count := 0;
      WaitArgs.WaitLevels[i].WaitGroups[j].IndexBase := Cntr;
      WaitArgs.WaitLevels[i].WaitGroups[j].WaitResult := wrFatal;
      WaitArgs.WaitLevels[i].WaitGroups[j].Index := -1;
      For k := Low(WaitArgs.WaitLevels[i].WaitGroups[j].Handles) to
               WaitGroupHandlesHigh(WaitArgs.WaitLevels[i].WaitGroups[j].Handles) do
        begin
          WaitArgs.WaitLevels[i].WaitGroups[j].Handles[k] := TempHPtr^;
          Inc(WaitArgs.WaitLevels[i].WaitGroups[j].Count);
          Inc(Cntr);
          Inc(TempHPtr); // should advance the pointer by a size of THandle
          If Cntr >= Count then
            Break{For j};
        end;
    end;
// initialize internals
WaitArgs.WaitInternals.ReadyCounter := Length(WaitArgs.WaitLevels);
WaitArgs.WaitInternals.DoneCounter := Length(WaitArgs.WaitLevels);
For i := Low(WaitArgs.WaitLevels) to High(WaitArgs.WaitLevels) do
  begin
    Inc(WaitArgs.WaitInternals.ReadyCounter,Length(WaitArgs.WaitLevels[i].WaitGroups));
    Inc(WaitArgs.WaitInternals.DoneCounter,Length(WaitArgs.WaitLevels[i].WaitGroups));
  end;
WaitArgs.WaitInternals.ReadyEvent := CreateEventW(nil,True,False,nil);
WaitArgs.WaitInternals.DoneEvent := CreateEventW(nil,True,False,nil);
If not WaitArgs.WaitParams.WaitAll then
  begin
    // releaser is used only when not waiting for all objects to be signaled
    WaitArgs.WaitInternals.ReleaserEvent := CreateEventW(nil,True,False,nil);
    // add releaser handle to all groups
    For i := Low(WaitArgs.WaitLevels) to High(WaitArgs.WaitLevels) do
      For j := Low(WaitArgs.WaitLevels[i].WaitGroups) to High(WaitArgs.WaitLevels[i].WaitGroups) do
        begin
          WaitArgs.WaitLevels[i].WaitGroups[j].Handles[WaitArgs.WaitLevels[i].WaitGroups[j].Count] :=
            WaitArgs.WaitInternals.ReleaserEvent;
          Inc(WaitArgs.WaitLevels[i].WaitGroups[j].Count);
        end;
  end;
WaitArgs.WaitInternals.FirstDone := UInt64(-1);
end;

//------------------------------------------------------------------------------

Function WaitForManyHandles_Postprocess(var WaitArgs: TWSOWaitArgs; out Index: Integer): TWaitResult;
begin
{$message 'implement'}
Result := wrSignaled;
// check for fatals in levels, then groups
// check for errors in levels, then groups
// check for msg or apc in levels other then the first and timeout in all levels (=invalid result)
// check for message or apc in the first level
// if still good, take the first and resolve index and result (timeout/signaled/abandoned)
end;

//------------------------------------------------------------------------------

Function WaitForManyHandles_Internal(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
var
  WaitArgs: TWSOWaitArgs;
begin
Index := -1;
If Count > 0 then
  begin
    If Count > MaxWaitObjCount(MsgWaitOptions) then
      begin
      {
        More than maximum waited objects (64/63).

        Split handles to levels and groups.  
        If message waiting is enabled, the first level (index 0) will wait for
        them, other levels and groups can just ignore this setting.
      }
        FillChar(WaitArgs,SizeOf(TWSOWaitArgs),0);
        // assign wait parameters
        WaitArgs.WaitParams.WaitAll := WaitAll;
        WaitArgs.WaitParams.Timeout := Timeout;
        WaitArgs.WaitParams.Alertable := Alertable;
        WaitArgs.WaitParams.MsgWaitOptions := MsgWaitOptions;
        WaitArgs.WaitParams.WakeMask := WakeMask;
        // do other preprocessing
        WaitForManyHandles_Preprocess(WaitArgs,Handles,Count);
        // do the waiting
        If not WaitAll then
          begin
          {
            Wait for at least one object to become signaled.

            As the waiting will be split into multiple threads, the first wait
            thread returning will cause the wait call to return too, but other
            threads might be still waiting.
            So we set the releaser to signaled, which will release all threads
            that are still waiting (they will be automatically freed).
          }
            WaitForManyHandles_One(@WaitArgs,Low(WaitArgs.WaitLevels));
            // at least one waiter thread returned, release all others
            SetEvent(WaitArgs.WaitInternals.ReleaserEvent);
          end
        // waiting for all objects to be signaled
        else WaitForManyHandles_All(@WaitArgs,Low(WaitArgs.WaitLevels));
      {
        Wait for all waits to return.
        Necessary for memory integrity - still running threads might access
        non-exiting memory, namely WaitArgs variable.
      }
        If WaitForSingleObject(WaitArgs.WaitInternals.DoneEvent,INFINITE) <> WAIT_OBJECT_0 then
          raise EWSOWaitError.Create('WaitForManyHandles_Internal: Failed to wait for done event.');
        // process result(s)
        Result := WaitForManyHandles_Postprocess(WaitArgs,Index);
      end  
    // there is less than or equal to maximum number of objects, do simple wait
    else Result := WaitForMultipleHandles_Sys(Handles,Count,WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
  end
else raise EWSOMultiWaitInvalidCount.Create('WaitForManyHandles_Internal: Empty handle array.');
end;

{===============================================================================
    Wait functions (N > MAX) - public functions
===============================================================================}

Function WaitForManyHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
begin
Result := WaitForManyHandles_Internal(Handles,Count,WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForManyHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult;
begin
Result := WaitForManyHandles_Internal(Handles,Count,WaitAll,Timeout,Index,Alertable,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForManyHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForManyHandles_Internal(Handles,Count,WaitAll,Timeout,Index,Alertable,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForManyHandles(Handles: PHandle; Count: Integer; WaitAll: Boolean): TWaitResult;
var
  Index:  Integer;
begin
Result := WaitForManyHandles_Internal(Handles,Count,WaitAll,INFINITE,Index,False,[],0);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForManyHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean; MsgWaitOptions: TMessageWaitOptions; WakeMask: DWORD): TWaitResult;
begin
If Length(Handles) > 0 then
  Result := WaitForManyHandles_Internal(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,Timeout,Index,Alertable,MsgWaitOptions,WakeMask)
else
  raise EWSOMultiWaitInvalidCount.Create('WaitForManyHandles: Empty handle array.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForManyHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; out Index: Integer; Alertable: Boolean = False): TWaitResult;
begin
If Length(Handles) > 0 then
  Result := WaitForManyHandles_Internal(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,Timeout,Index,Alertable,[],0)
else
  raise EWSOMultiWaitInvalidCount.Create('WaitForManyHandles: Empty handle array.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForManyHandles(Handles: array of THandle; WaitAll: Boolean; Timeout: DWORD; Alertable: Boolean = False): TWaitResult;
var
  Index:  Integer;
begin
If Length(Handles) > 0 then
  Result := WaitForManyHandles_Internal(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,Timeout,Index,Alertable,[],0)
else
  raise EWSOMultiWaitInvalidCount.Create('WaitForManyHandles: Empty handle array.');
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function WaitForManyHandles(Handles: array of THandle; WaitAll: Boolean): TWaitResult;
var
  Index:  Integer;
begin
If Length(Handles) > 0 then
  Result := WaitForManyHandles_Internal(Addr(Handles[Low(Handles)]),Length(Handles),WaitAll,INFINITE,Index,False,[],0)
else
  raise EWSOMultiWaitInvalidCount.Create('WaitForManyHandles: Empty handle array.');
end;


(*

{===============================================================================
    Utility functions - internal functions
===============================================================================}


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

*)
{===============================================================================
--------------------------------------------------------------------------------
                               Utility functions
--------------------------------------------------------------------------------
===============================================================================}

Function WaitResultToStr(WaitResult: TWaitResult): String;
const
  WR_STRS: array[TWaitResult] of String = ('Signaled','Abandoned','IOCompletion','Message','Timeout','Error','Fatal');
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

procedure HandleArrayItemsStrideCheck(Handles: array of THandle);
var
  TestArray:  array of THandle;
begin
{
  Check whether array of handles (including open array) does or does not have
  some gaps (due to alignment) between items - current implementation assumes
  it doesn't.
}
If (PtrUInt(Addr(Handles[Succ(Low(Handles))])) - PtrUInt(Addr(Handles[Low(Handles)]))) <> SizeOf(THandle) then
  raise EWSOException.Create('HandleArrayItemsStrideCheck: Unsupported implementation detail (open array items alignment).');
SetLength(TestArray,2);
If (PtrUInt(Addr(TestArray[Succ(Low(TestArray))])) - PtrUInt(Addr(TestArray[Low(TestArray)]))) <> SizeOf(THandle) then
  raise EWSOException.Create('HandleArrayItemsStrideCheck: Unsupported implementation detail (array items alignment).');
end;

//------------------------------------------------------------------------------

procedure Initialize;
begin
HandleArrayItemsStrideCheck([THandle(0),THandle(1)]);
end;

//------------------------------------------------------------------------------

initialization
  Initialize;

end.

