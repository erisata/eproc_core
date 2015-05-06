%/--------------------------------------------------------------------
%| Copyright 2013-2015 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%%
%%% This module can be used in callback modules for the `eproc_fsm`
%%% to manage timers associated with the FSM.
%%%
%%% To be done in this module (TODO):
%%%
%%%   * should we use `https://github.com/choptastic/qdate` instead of `timestamp_*` functions?
%%%
-module(eproc_timer).
-behaviour(eproc_fsm_attr).
-export([set/4, set/3, set/2, cancel/1]).
-export([
    duration_to_ms/1,
    duration_format/2,
    duration_parse/2,
    timestamp_after/2,
    timestamp_before/2,
    timestamp/2,
    timestamp_diff_us/2,
    timestamp_diff/2,
    timestamp_format/2,
    timestamp_parse/2
]).
-export([init/2, handle_created/4, handle_updated/5, handle_removed/3, handle_event/4]).
-export_type([duration/0]).
-include("eproc.hrl").


-type duration_elem() :: {integer(), ms | s | sec | min | hour | day | week | month | year}.

%%
%%  Describes duration in human readable format.
%%
-type duration_spec() :: duration_elem() | [duration_elem()] | integer().


-define(MAX_ATOMIC_DELAY, 4294967295).
-define(UNIX_BIRTH, 62167219200).
-define(MEGA, 1000000).


%%
%%  Persistent state.
%%
-record(data, {
    start       :: timestamp(),
    delay       :: duration(),
    event_msg   :: term(),
    event_cid   :: msg_cid(),
    event_type  :: binary()
}).

%%
%%  Runtime state.
%%
-record(state, {
    ref
}).



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Set new or update existing timer.
%%
%%  `Name`
%%  :   is a name of the timer to create or update.
%%  `Time`
%%  :   specified, when the timer should be fired.
%%      It can be absolute timestamp of relative
%%      duration, to fire at from now.
%%  `Event`
%%  :   is an event to be sent to FSM.
%%  `Scope`
%%  :   specifies validity scope of the timer.
%%      Timer will be automatically canceled, if the FSM wil exit
%%      the specific scope. Use `[]` for timers valid for the entire
%%      lifecycle of the FSM. A special term can be used for the
%%      scope: `next`. It represents a state, that will be entered
%%      after the current transition.
%%
-spec set(
        Name  :: term(),
        Time  :: timestamp() | duration(),
        Event :: term(),
        Scope :: scope()
    ) ->
        ok.
set(Name, Time = {M, S, U}, Event, Scope) when is_integer(M), is_integer(S), is_integer(U) ->
    Start = os:timestamp(),
    After = timestamp_diff(Time, Start),
    set_timer(Name, After, Start, Event, Scope);

set(Name, Time, Event, Scope) ->
    Start = os:timestamp(),
    After = Time,
    set_timer(Name, After, Start, Event, Scope).


%%
%%  Shorthand for the `set/4` function.
%%  Assumes name is undefined.
%%
set(After, Event, Scope) ->
    set(undefined, After, Event, Scope).


%%
%%  Shorthand for the `set/4` function.
%%  Assumes name is undefined and the scope is `next`.
%%
set(After, Event) ->
    set(undefined, After, Event, next).


%%
%%  Cancels not-yet-fired timer by its name.
%%
-spec cancel(
        Name :: term()
    ) ->
        ok |
        {error, Reason :: term()}.

cancel(Name) ->
    eproc_fsm_attr:action(?MODULE, Name, {timer, remove}).


%%
%%  Converts human readable duration specification to milliseconds.
%%  Conversion is made approximatly, assuming all months are of 30 days
%%  and years are of 365 days.
%%
%%  Example specs:
%%
%%      {3, min}
%%      {100, hour}
%%      [{1, min}, {10, s}]
%%
-spec duration_to_ms(duration()) -> integer().

duration_to_ms({N, us}) ->
    N div 1000;

duration_to_ms({N, ms}) ->
    N;

duration_to_ms({N, s}) ->
    N * 1000;

duration_to_ms({N, sec}) ->
    N * 1000;

duration_to_ms({N, min}) ->
    N * 60 * 1000;

duration_to_ms({N, hour}) ->
    N * 60 * 60 * 1000;

duration_to_ms({N, day}) ->
    N * 24 * 60 * 60 * 1000;

duration_to_ms({N, week}) ->
    N * 7 * 24 * 60 * 60 * 1000;

duration_to_ms({N, month}) ->
    N * 30 * 24 * 60 * 60 * 1000;

duration_to_ms({N, year}) ->
    N * 365 * 24 * 60 * 60 * 1000;

duration_to_ms(Spec) when is_integer(Spec) ->
    Spec;

duration_to_ms(Spec) when is_list(Spec) ->
    lists:sum(lists:map(fun duration_to_ms/1, Spec)).


%%
%%  Format duration according to some format.
%%  - iso8601:
%%      Splits duration into days, hours, minutes, seconds and milisecons.
%%      Carry over values are not obtained (thus 120 s will be formatted as 2 min).
%%      If miliseconds are not 0, always displays 3 digits.
%%      More information about format:
%%      http://en.wikipedia.org/wiki/ISO_8601#Durations
%%      http://www.datypic.com/sc/xsd/t-xsd_duration.html
%%
duration_format(Duration, iso8601) ->
    DurationMs = duration_to_ms(Duration),
    SplitFun = fun (Divisor, {Dividend, List}) ->
        Remainder = Dividend rem Divisor,
        NewDividend = Dividend div Divisor,
        {NewDividend, [Remainder | List]}
    end,
    {Ds, [Hs, Mins, Secs, MSecs]} = lists:foldl(SplitFun, {DurationMs, []}, [1000, 60, 60, 24]),
    SecMSecs = case {Secs, MSecs} of
        {0, 0} -> "";
        {S, 0} -> lists:concat([S, "S"]);
        {S, MS} -> lists:flatten(io_lib:format("~B.~3.10.0BS", [S, MS]))
    end,
    FormatFun= fun
        ({0, _}) -> false;
        ({Number, Letter}) -> {true, lists:concat([Number, Letter])}
    end,
    Date = lists:filtermap(FormatFun, lists:zip([Ds], ["D"])),  % Just in case there will be a need to convert to years
    Time = lists:filtermap(FormatFun, lists:zip([Hs, Mins], ["H", "M"])),
    DateFmt = lists:concat(Date),
    TimeFmt = lists:concat([lists:concat(Time),  SecMSecs]),
    Result = case {DateFmt, TimeFmt} of
        {"", ""} -> "PT0S";
        {D, ""} -> lists:append("P", D);
        {D, T} -> lists:concat(["P", D, "T", T])
    end,
    erlang:list_to_binary(Result).

%%
%%  Parse duration according to some format.
%%
duration_parse(undefined, _Format) ->
    undefined;

duration_parse(null, _Format) ->
    undefined;

duration_parse(Duration, iso8601) when is_list(Duration) ->
    SplitFun= fun
        ($T) -> false;
        (_)  -> true
    end,
    {[$P | Date], TTime} = lists:splitwith(SplitFun, Duration),
    DateParse = duration_parser(Date, [], [{$Y,year},{$M,month},{$D,day}], []),
    case TTime of
        [$T | Time] ->
            duration_parser(Time, [], [{$H,hour},{$M,min},{$S,s}], DateParse);
        [] ->
            DateParse
    end.


%%
%% Helper function for duration_parse/2
%% The parameters are:
%%
%%   * String to be parsed;
%%   * Buffer of previously parsed tokens;
%%   * List of pairs {Matcher,Atom}, where Matcher is a match symbol and Atom is respective atom of duration record.
%%   * It is use to force a certain order of duration elements.
%%   * Result is accumulator of parsed duration.
%%
duration_parser("", [], _, Result) ->
    Result;

duration_parser(String, [], MatchList, Result) ->
    {ok, [Int], RestString} = io_lib:fread("~d", String),
    duration_parser(RestString, [Int], MatchList, Result);

duration_parser([Matcher | RestString], [Int], [{Matcher, Atom} | RestList], Result) when erlang:is_integer(Int) ->
    duration_parser(RestString, [], RestList, [{Int, Atom} | Result]);

duration_parser([$. | RestString], [Int], MatchList, Result) ->
    duration_parser(RestString, [$., "", Int], MatchList, Result);

duration_parser([Char | RestString], [$., FractPart, WholePart], MatchList, Result) when $0 =< Char, Char =< $9 ->
    duration_parser(RestString, [$., [Char|FractPart], WholePart], MatchList, Result);

duration_parser([$S | RestString], [$., FractPart, WholePart], MatchList, Result) ->
    FractPartOrder = lists:reverse(FractPart),
    FractPartFull = case string:len(FractPartOrder) of
        0 -> "0";
        1 -> lists:append(FractPartOrder,"00");
        2 -> lists:append(FractPartOrder,"0");
        3 -> FractPartOrder;
        N when N > 3 -> string:substr(FractPartOrder, 1, 3)
    end,
    {ok, [FractPartNumber], ""} = io_lib:fread("~d", FractPartFull),
    duration_parser([$S | RestString], [WholePart], MatchList, [{FractPartNumber, ms} | Result]);

duration_parser(String, [Int], [{_, _} | RestList], Result) ->
    duration_parser(String, [Int], RestList, Result).


%%
%%  Returns a timestamp that is in Duration after Timestamp.
%%
-spec timestamp_after(duration(), timestamp()) -> timestamp().

timestamp_after(Duration, {MSec, Sec, USec}) ->
    DurationMS = duration_to_ms(Duration),
    OldTSUSecs = ((MSec * ?MEGA) + Sec) * ?MEGA + USec,
    NewTSUSecs = OldTSUSecs + (DurationMS * 1000),
    NewTSSecs  = NewTSUSecs div ?MEGA,
    NewUSec = NewTSUSecs rem ?MEGA,
    NewSec  = NewTSSecs rem ?MEGA,
    NewMSec = NewTSSecs div ?MEGA,
    {NewMSec, NewSec, NewUSec}.


%%
%%  Returns a timestamp that is in Duration before Timestamp.
%%
-spec timestamp_before(duration(), timestamp()) -> timestamp().

timestamp_before(Duration, Timestamp) ->
    DurationMS = duration_to_ms(Duration),
    timestamp_after(-DurationMS, Timestamp).


%%
%%  Converts datetime to timestamp.
%%
-spec timestamp(
        DateTime ::
            calendar:datetime() |
            calendar:date() |
            {calendar:date(), calendar:time(), USec :: integer()} |
            undefined | null,
        Timezone :: local | utc
    ) ->
        timestamp() |
        undefined.

timestamp(undefined, _) ->
    undefined;

timestamp(null, _) ->
    undefined;

timestamp({Y, M, D}, Timezone) when is_integer(Y), is_integer(M), is_integer(D) ->
    timestamp({{Y, M, D}, {0, 0, 0}, 0}, Timezone);

timestamp({{Y, M, D}, {H, Mi, S}}, Timezone) ->
    timestamp({{Y, M, D}, {H, Mi, S}, 0}, Timezone);

timestamp({Date = {_Y, _M, _D}, Time = {_H, _Mi, _S}, USec}, local) ->
    [{UniversalDate, UniversalTime}|_] = calendar:local_time_to_universal_time_dst({Date, Time}),
    timestamp({UniversalDate, UniversalTime, USec}, utc);

timestamp({Date = {_Y, _M, _D}, Time = {_H, _Mi, _S}, USec}, utc) ->
    Seconds = calendar:datetime_to_gregorian_seconds({Date, Time}) - ?UNIX_BIRTH,
    {Seconds div ?MEGA, Seconds rem ?MEGA, USec}.



%%
%%  Returns difference of Time2 and Time1 (Time2 - Time1) in microseconds.
%%
-spec timestamp_diff_us(
        Timestamp2 :: timestamp(),
        Timestamp1 :: timestamp()
    ) ->
        timestamp().

timestamp_diff_us(undefined, _) ->
    undefined;

timestamp_diff_us(_, undefined) ->
    undefined;

timestamp_diff_us({T2M, T2S, T2U}, {T1M, T1S, T1U}) ->
    T1 = (T1M * ?MEGA + T1S) * ?MEGA + T1U,
    T2 = (T2M * ?MEGA + T2S) * ?MEGA + T2U,
    T2 - T1.


%%
%%  Returns duration between Time1 and Time2 (Time2 - Time1).
%%  Duration is returned in days, and time is decomposed to
%%  hours, minutes, seconds, millis and microseconds.
%%
-spec timestamp_diff(
        Timestamp2 :: timestamp(),
        Timestamp1 :: timestamp()
    ) ->
        duration().

timestamp_diff(Timestamp2, Timestamp1) ->
    case timestamp_diff_us(Timestamp2, Timestamp1) of
        undefined ->
            undefined;
        Diff ->
            case timestamp_diff(Diff, [{us, 1000}, {ms, 1000}, {sec, 60}, {min, 60}, {hour, 24}], []) of
                [Single] -> Single;
                Multiple -> Multiple
            end
    end.

timestamp_diff(0, _, []) ->
    {0, ms};

timestamp_diff(0, _, Result) ->
    Result;

timestamp_diff(Diff, [], Result) ->
    [{Diff, day} | Result];

timestamp_diff(Diff, [{Unit, Max} | NextUnit], Result) ->
    This = Diff rem Max,
    Next = Diff div Max,
    NewResult = case This of
        0 -> Result;
        X -> [{X, Unit} | Result]
    end,
    timestamp_diff(Next, NextUnit, NewResult).


%%
%%  Format date according to some format.
%%
timestamp_format(Timestamp, iso8601) ->
    timestamp_format(Timestamp, {iso8601, utc});

timestamp_format(Timestamp, {iso8601, TZ}) ->
    timestamp_format(Timestamp, {iso8601, TZ, us});

timestamp_format(Timestamp = {_M, _S, US}, {iso8601, utc, Preciseness}) ->
    {{Y, M, D}, {H, Mi, S}} = calendar:now_to_universal_time(Timestamp),
    MS = US div 1000,
    Date = case Preciseness of
        us  -> io_lib:format("~B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0B.~6.10.0BZ", [Y, M, D, H, Mi, S, US]);
        ms  -> io_lib:format("~B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0B.~3.10.0BZ", [Y, M, D, H, Mi, S, MS]);
        sec -> io_lib:format("~B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0BZ",          [Y, M, D, H, Mi, S])
    end,
    erlang:iolist_to_binary(Date).


%%
%%  Parse date according to some format.
%%
timestamp_parse(undefined, _Format) ->
    undefined;

timestamp_parse(null, _Format) ->
    undefined;

timestamp_parse(TimestampBin, iso8601) when is_binary(TimestampBin) ->
    <<
        Year:4/binary, "-", Month:2/binary, "-", Day:2/binary, "T",
        Hour:2/binary, ":", Min:2/binary,   ":", Sec:2/binary, Rest/binary
    >> = TimestampBin,
    {USec, TZone} = case Rest of
        <<>>                      -> {0, local};
        <<"Z">>                   -> {0, utc};
        <<".", US:6/binary>>      -> {binary_to_integer(US), local};
        <<".", US:6/binary, "Z">> -> {binary_to_integer(US), utc};
        <<".", MS:3/binary>>      -> {binary_to_integer(MS) * 1000, local};
        <<".", MS:3/binary, "Z">> -> {binary_to_integer(MS) * 1000, utc}
    end,
    Date = {binary_to_integer(Year), binary_to_integer(Month), binary_to_integer(Day)},
    Time = {binary_to_integer(Hour), binary_to_integer(Min), binary_to_integer(Sec)},
    timestamp({Date, Time, USec}, TZone).



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(InstId, ActiveAttrs) ->
    InitTimerFun = fun (Attr = #attribute{attr_id = AttrId, data = Data}) ->
        {ok, State} = start_timer(InstId, AttrId, Data),
        {Attr, State}
    end,
    Started = lists:map(InitTimerFun, ActiveAttrs),
    {ok, Started}.


%%
%%  Attribute created.
%%
handle_created(InstId, #attribute{attr_id = AttrId}, {timer, After, Start, EventMsgCId, EventMsgType, Event}, _Scope) ->
    Data = #data{
        start = Start,
        delay = After,
        event_msg = Event,
        event_cid = EventMsgCId,
        event_type = EventMsgType
    },
    {ok, State} = start_timer(InstId, AttrId, Data),
    {create, Data, State, false};

handle_created(_InstId, _Attribute, {timer, remove}, _Scope) ->
    {error, {unknown_timer}}.


%%
%%  Attribute updated by user.
%%
handle_updated(InstId, Attribute, AttrState, {timer, After, Start, EventMsgCId, EventMsgType, Event}, _Scope) ->
    #attribute{attr_id = AttrId} = Attribute,
    NewData = #data{
        start = Start,
        delay = After,
        event_msg = Event,
        event_cid = EventMsgCId,
        event_type = EventMsgType
    },
    ok = stop_timer(AttrState),
    {ok, NewState} = start_timer(InstId, AttrId, NewData),
    {update, NewData, NewState, false};

handle_updated(_InstId, _Attribute, AttrState, {timer, remove}, _Scope) ->
    ok = stop_timer(AttrState),
    {remove, explicit, false}.


%%
%%  Attribute removed by `eproc_fsm`.
%%
handle_removed(_InstId, _Attribute, AttrState) ->
    ok = stop_timer(AttrState),
    {ok, false}.


%%
%%  Handle timer events.
%%
handle_event(InstId, Attribute, _State, long_delay) ->
    #attribute{
        attr_id = AttrId,
        data = AttrData
    } = Attribute,
    {ok, NewState} = start_timer(InstId, AttrId, AttrData),
    {handled, NewState};

handle_event(_InstId, Attribute, _State, fired) ->
    #attribute{
        attr_id = AttrId,
        data = #data{event_msg = Event, event_cid = EventMsgCId, event_type = EventMsgType}
    } = Attribute,
    Trigger = #trigger_spec{
        type = timer,
        source = {attr, AttrId},
        message = Event,
        msg_cid = EventMsgCId,
        msg_type_fun = fun (R, E) -> eproc_fsm:resolve_event_type_const(R, EventMsgType, E) end,
        sync = false,
        reply_fun = undefined,
        src_arg = false
    },
    Action = {remove, fired},
    {trigger, Trigger, Action, false}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Create or update a timer.
%%
set_timer(Name, After, Start, Event, Scope) ->
    {ok, InstId} = eproc_fsm:id(),
    Src = {inst, InstId},
    Dst = {timer, Name},
    EventMsgType = eproc_fsm:resolve_event_type(timer, Event),
    {ok, EventMsgCId} = eproc_fsm:register_sent_msg(Src, Dst, undefined, EventMsgType, Event, Start),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Start, EventMsgCId, EventMsgType, Event}, Scope).


%%
%%  Starts a timer.
%%
start_timer(InstId, AttrId, #data{start = Start, delay = DelaySpec}) ->
    Now = os:timestamp(),
    Delay = duration_to_ms(DelaySpec),
    Left = Delay - (timer:now_diff(Now, Start) div 1000),
    if
        Left < 0 ->
            {ok, EventMsg} = eproc_fsm_attr:make_event(?MODULE, InstId, AttrId, fired),
            self() ! EventMsg,
            {ok, #state{ref = undefined}};
        Left > ?MAX_ATOMIC_DELAY ->
            {ok, EventMsg} = eproc_fsm_attr:make_event(?MODULE, InstId, AttrId, long_delay),
            TimerRef = erlang:send_after(?MAX_ATOMIC_DELAY, self(), EventMsg),
            {ok, #state{ref = TimerRef}};
        true ->
            {ok, EventMsg} = eproc_fsm_attr:make_event(?MODULE, InstId, AttrId, fired),
            TimerRef = erlang:send_after(Left, self(), EventMsg),
            {ok, #state{ref = TimerRef}}
    end.


%%
%%  Stops a timer.
%%
stop_timer(#state{ref = undefined}) ->
    ok; % Timer was fired immediatelly.

stop_timer(#state{ref = TimerRef}) ->
    erlang:cancel_timer(TimerRef),
    ok.


