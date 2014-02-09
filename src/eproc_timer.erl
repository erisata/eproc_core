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
-export([set/4, set/3, set/2, cancel/1]).
-export([init/1, handle_created/3, handle_updated/4, handle_removed/2, handle_event/3]).
-include("eproc.hrl").

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
    ok = eproc_fsm:register_message({inst, eproc_fsm:id()}, {timer, Name}, Event, undefined),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Event}, Scope).


%%
%%
%%
set(After, Event, Scope) ->
    Name = undefined,
    ok = eproc_fsm:register_message({inst, eproc_fsm:id()}, {timer, Name}, Event, undefined),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Event}, Scope).


%%
%%
%%
set(After, Event) ->
    Name = undefined,
    ok = eproc_fsm:register_message({inst, eproc_fsm:id()}, {timer, Name}, Event, undefined),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Event}, next).


%%
%%
%%
cancel(Name) ->
    eproc_fsm_attr:action(?MODULE, Name, {timer, remove}).



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
    {create, Data, State};

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
    {update, NewData, NewState};

handle_updated(_Attribute, AttrState, {timer, remove}, _Scope) ->
    ok = stop_timer(AttrState),
    {remove, explicit}.


%%
%%  Attribute removed by `eproc_fsm`.
%%
handle_removed(_Attribute, State) ->
    ok = stop_timer(State).


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
    Trigger = {timer, Name, Event},
    Action = {remove, fired},
    {trigger, Trigger, Action}. %% TODO: Trigger source should be included into the trigger or not?



%% =============================================================================
%%  Internal functions.
%% =============================================================================


%%
%%  Starts a timer.
%%
start_timer(AttrId, #data{start = Start, delay = Delay}) ->
    Now = erlang:now(),
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


