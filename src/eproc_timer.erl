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
-export([set/4, set/3, set/2, cancel/1, duration_to_ms/1]).
-export([init/1, handle_created/3, handle_updated/4, handle_removed/2, handle_event/3]).
-export_type([duration/0]).
-include("eproc.hrl").


-type duration_elem() :: {integer(), ms | s | sec | min | hour | day | week | month | year}.

%%
%%  Describes duration in human readable format.
%%
-type duration_spec() :: duration_elem() | [duration_elem()] | integer().


-define(MAX_ATOMIC_DELAY, 4294967295).

%%
%%  Persistent state.
%%
-record(data, {
    start,
    delay,
    event
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
%%
%%
set(Name, After, Event, Scope) ->
    Now = erlang:now(),
    {ok, registered} = eproc_fsm:register_message({inst, eproc_fsm:id()}, {timer, Name}, {msg, Event, Now}, undefined),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Event}, Scope).


%%
%%
%%
set(After, Event, Scope) ->
    Now = erlang:now(),
    Name = undefined,
    {ok, registered} = eproc_fsm:register_message({inst, eproc_fsm:id()}, {timer, Name}, {msg, Event, Now}, undefined),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Event}, Scope).


%%
%%
%%
set(After, Event) ->
    Now = erlang:now(),
    Name = undefined,
    {ok, registered} = eproc_fsm:register_message({inst, eproc_fsm:id()}, {timer, Name}, {msg, Event, Now}, undefined),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Event}, next).


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



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(ActiveAttrs) ->
    InitTimerFun = fun (Attr = #attribute{attr_id = AttrId, data = Data}) ->
        {ok, State} = start_timer(AttrId, Data),
        {Attr, State}
    end,
    Started = lists:map(InitTimerFun, ActiveAttrs),
    {ok, Started}.


%%
%%  Attribute created.
%%
handle_created(#attribute{attr_id = AttrId}, {timer, After, Event}, _Scope) ->
    Data = #data{start = erlang:now(), delay = After, event = Event},
    {ok, State} = start_timer(AttrId, Data),
    {create, Data, State, false};

handle_created(_Attribute, {timer, remove}, _Scope) ->
    {error, {unknown_timer}}.


%%
%%  Attribute updated by user.
%%
handle_updated(Attribute, AttrState, {timer, After, Event}, _Scope) ->
    #attribute{attr_id = AttrId} = Attribute,
    NewData = #data{start = erlang:now(), delay = After, event = Event},
    ok = stop_timer(AttrState),
    {ok, NewState} = start_timer(AttrId, NewData),
    {update, NewData, NewState, false};

handle_updated(_Attribute, AttrState, {timer, remove}, _Scope) ->
    ok = stop_timer(AttrState),
    {remove, explicit, false}.


%%
%%  Attribute removed by `eproc_fsm`.
%%
handle_removed(_Attribute, State) ->
    ok = stop_timer(State),
    {ok, false}.


%%
%%
%%
handle_event(Attribute, _State, long_delay) ->
    #attribute{
        attr_id = AttrId,
        data = AttrData
    } = Attribute,
    {ok, NewState} = start_timer(AttrId, AttrData),
    {handled, NewState};

handle_event(Attribute, _State, fired) ->
    #attribute{
        name = Name,
        data = #data{event = Event}
    } = Attribute,
    Trigger = #trigger_spec{
        type = timer,
        source = Name,
        message = Event,
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
start_timer(AttrId, #data{start = Start, delay = DelaySpec}) ->
    Now = erlang:now(),
    Delay = duration_to_ms(DelaySpec),
    Left = Delay - (timer:now_diff(Start, Now) div 1000),
    if
        Left < 0 ->
            {ok, EventMsg} = eproc_fsm_attr:make_event(?MODULE, AttrId, fired),
            self() ! EventMsg,
            {ok, #state{ref = undefined}};
        Left > ?MAX_ATOMIC_DELAY ->
            {ok, EventMsg} = eproc_fsm_attr:make_event(?MODULE, AttrId, long_delay),
            TimerRef = erlang:send_after(?MAX_ATOMIC_DELAY, self(), EventMsg),
            {ok, #state{ref = TimerRef}};
        true ->
            {ok, EventMsg} = eproc_fsm_attr:make_event(?MODULE, AttrId, fired),
            TimerRef = erlang:send_after(Left, self(), EventMsg),
            {ok, #state{ref = TimerRef}}
    end.


%%
%%  Stops a timer.
%%
stop_timer(#state{ref = TimerRef}) ->
    erlang:cancel_timer(TimerRef),
    ok.


