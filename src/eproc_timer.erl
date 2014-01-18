%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, Ltd.
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
-export([started/1, created/3, updated/2, removed/1]).
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
-record(rtdata, {
    ref
}).



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
set(Name, After, Event, Scope) ->
    ok = eproc_fsm:register_message({timer, Name}, Event),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Event}, Scope).


%%
%%
%%
set(After, Event, Scope) ->
    Name = undefined,
    ok = eproc_fsm:register_message({timer, Name}, Event),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Event}, Scope).


%%
%%
%%
set(After, Event) ->
    Name = undefined,
    ok = eproc_fsm:register_message({timer, Name}, Event),
    ok = eproc_fsm_attr:action(?MODULE, Name, {timer, After, Event}, next).


%%
%%
%%
cancel(Name) ->
    eproc_fsm_attr:set(?MODULE, Name, {timer, remove}).



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
started(ActiveAttrs) ->
    Started = [ start_timer(A) || A <- ActiveAttrs ],
    {ok, Started}.


%%
%%  Attribute created.
%%
created(Name, {timer, After, Event}, _Scope) ->
    {error, undefined}; % TODO

created(Name, {timer, remove}, _Scope) ->
    {error, {unknown_timer, Name}}.


%%
%%  Attribute updated by user.
%%
updated(Attribute, {timer, After, Event}) ->
    {error, undefined}; % TODO

updated(Attribute, {timer, remove}) ->
    {error, undefined}. % TODO


%%
%%  Attribute removed by `eproc_fsm`.
%%
removed(Attribute) ->
    {error, undefined}. % TODO



%% =============================================================================
%%  Internal functions.
%% =============================================================================



start_timer(Attribute) ->
    #attribute{data = Data} = Attribute,
    #data{start = Start, delay = Delay, event = Event} = Data,
    Now = erlang:now(),
    Left = Delay - (timer:now_diff(Start, Now) div 1000),
    if
        Left < 0 ->
            {ok, EventMsg} = eproc_fsm_attr:make_fsm_event(Attribute, Event),   % TODO: Implement
            self() ! EventMsg,
            {ok, #rtdata{ref = delayed}};
        Left > ?MAX_ATOMIC_DELAY ->
            {ok, EventMsg} = eproc_fsm_attr:make_attr_event(Attribute, long_delay),   % TODO: Implement
            TimerRef = erlang:send_after(?MAX_ATOMIC_DELAY, self(), EventMsg),
            {ok, #rtdata{ref = TimerRef}};
        true ->
            {ok, EventMsg} = eproc_fsm_attr:make_attr_event(Attribute, Event),   % TODO: Implement
            TimerRef = erlang:send_after(Left, self(), EventMsg),
            {ok, #rtdata{ref = TimerRef}}
    end.



