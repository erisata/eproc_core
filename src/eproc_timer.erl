%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, UAB (Ltd.)
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

%%
%%  This module can be used in callback modules for the `eproc_fsm`
%%  to manage timers associated with the FSM.
%%
-module(eproc_timer).
-behaviour(eproc_fsm_attr).
-export([set/4, set/3, set/2, cancel/1, duration_to_ms/1, timestamp_after/2, timestamp_before/2, timestamp/1]).
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
    event_cid   :: msg_cid()
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
%%  TODO: Set timer by exact timestamp.
%%
set(Name, After, Event, Scope) ->
    Now = os:timestamp(),
    {ok, InstId} = eproc_fsm:id(),
    Src = {inst, InstId},
    Dst = {timer, Name},
    {ok, EventMsgCId} = eproc_fsm:register_sent_msg(Src, Dst, undefined, Event, Now),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, EventMsgCId, Event}, Scope).


%%
%%
%%
set(After, Event, Scope) ->
    set(undefined, After, Event, Scope).


%%
%%
%%
set(After, Event) ->
    set(undefined, After, Event, next).


%%
%%
%%
cancel(Name) ->
    eproc_fsm_attr:action(?MODULE, Name, {timer, remove}).


%%
%%  Converts human readable duration specification to milliseconds.
%%  Conversion is made approximatly, assuming all months are of 30 days
%%  and years are of 365 days.
%%
%%  Esample specs:
%%
%%      {3, min}
%%      {100, hour}
%%      [{1, min}, {10, s}]
%%
-spec duration_to_ms(duration()) -> integer().

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
            undefined | null
    ) ->
        timestamp() |
        undefined.

timestamp(undefined) ->
    undefined;

timestamp(null) ->
    undefined;

timestamp({Y, M, D}) when is_integer(Y), is_integer(M), is_integer(D) ->
    timestamp({{Y, M, D}, {0, 0, 0}, 0});

timestamp({{Y, M, D}, {H, Mi, S}}) ->
    timestamp({{Y, M, D}, {H, Mi, S}, 0});

timestamp({Date = {_Y, _M, _D}, Time = {_H, _Mi, _S}, USec}) ->
    Seconds = calendar:datetime_to_gregorian_seconds({Date, Time}) - ?UNIX_BIRTH,
    {Seconds div ?MEGA, Seconds rem ?MEGA, USec}.



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(InstId, ActiveAttrs) ->
    InitTimerFun = fun (Attr = #attribute{attr_id = AttrNr, data = Data}) ->
        {ok, State} = start_timer(InstId, AttrNr, Data),
        {Attr, State}
    end,
    Started = lists:map(InitTimerFun, ActiveAttrs),
    {ok, Started}.


%%
%%  Attribute created.
%%
handle_created(InstId, #attribute{attr_id = AttrNr}, {timer, After, EventMsgCId, Event}, _Scope) ->
    Data = #data{
        start = os:timestamp(),
        delay = After,
        event_msg = Event,
        event_cid = EventMsgCId
    },
    {ok, State} = start_timer(InstId, AttrNr, Data),
    {create, Data, State, false};

handle_created(_InstId, _Attribute, {timer, remove}, _Scope) ->
    {error, {unknown_timer}}.


%%
%%  Attribute updated by user.
%%
handle_updated(InstId, Attribute, AttrState, {timer, After, EventMsgCId, Event}, _Scope) ->
    #attribute{attr_id = AttrNr} = Attribute,
    NewData = #data{
        start = os:timestamp(),
        delay = After,
        event_msg = Event,
        event_cid = EventMsgCId
    },
    ok = stop_timer(AttrState),
    {ok, NewState} = start_timer(InstId, AttrNr, NewData),
    {update, NewData, NewState, false};

handle_updated(_InstId, _Attribute, AttrState, {timer, remove}, _Scope) ->
    ok = stop_timer(AttrState),
    {remove, explicit, false}.


%%
%%  Attribute removed by `eproc_fsm`.
%%
handle_removed(_InstId, _Attribute, State) ->
    ok = stop_timer(State),
    {ok, false}.


%%
%%  Handle timer events.
%%
handle_event(InstId, Attribute, _State, long_delay) ->
    #attribute{
        attr_id = AttrNr,
        data = AttrData
    } = Attribute,
    {ok, NewState} = start_timer(InstId, AttrNr, AttrData),
    {handled, NewState};

handle_event(_InstId, Attribute, _State, fired) ->
    #attribute{
        name = Name,
        data = #data{event_msg = Event, event_cid = EventMsgCId}
    } = Attribute,
    Trigger = #trigger_spec{
        type = timer,
        source = Name,
        message = Event,
        msg_cid = EventMsgCId,
        sync = false,
        reply_fun = undefined,
        src_arg = true
    },
    Action = {remove, fired},
    {trigger, Trigger, Action, false}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================


%%
%%  Starts a timer.
%%
start_timer(InstId, AttrNr, #data{start = Start, delay = DelaySpec}) ->
    Now = os:timestamp(),
    Delay = duration_to_ms(DelaySpec),
    Left = Delay - (timer:now_diff(Start, Now) div 1000),
    if
        Left < 0 ->
            {ok, EventMsg} = eproc_fsm_attr:make_event(?MODULE, InstId, AttrNr, fired),
            self() ! EventMsg,
            {ok, #state{ref = undefined}};
        Left > ?MAX_ATOMIC_DELAY ->
            {ok, EventMsg} = eproc_fsm_attr:make_event(?MODULE, InstId, AttrNr, long_delay),
            TimerRef = erlang:send_after(?MAX_ATOMIC_DELAY, self(), EventMsg),
            {ok, #state{ref = TimerRef}};
        true ->
            {ok, EventMsg} = eproc_fsm_attr:make_event(?MODULE, InstId, AttrNr, fired),
            TimerRef = erlang:send_after(Left, self(), EventMsg),
            {ok, #state{ref = TimerRef}}
    end.


%%
%%  Stops a timer.
%%
stop_timer(#state{ref = TimerRef}) ->
    erlang:cancel_timer(TimerRef),
    ok.


