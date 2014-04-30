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
%%  Example FSM implementation, that uses `eproc_router`.
%%
-module(eproc_fsm__order).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([new/0, named/1, reset/1, skip/1, close/1, next/1, get/1, last/1, flip/1, exists/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include("eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Start unnamed seq.
%%  This function uses sync create event.
%%
new(OrderId) ->
    lager:debug("Creating new Order(~p).", [OrderId]),
    StartOpts = [{register, id}],
    CreateOpts = [{start_spec, {default, StartOpts}}],
    {ok, _FsmRef} = eproc_fsm:sync_send_create_event(?MODULE, {}, {new, OrderId}, CreateOpts),
    ok.


%%
%%  Start named seq.
%%  This function uses asynchronous initial event.
%%
named(Name) ->
    lager:debug("Creating new named SEQ."),
    StartOpts = [{register, both}, {start_sync, true}],
    CreateOpts = [{name, Name}, {start_spec, {default, StartOpts}}],
    {ok, FsmRef} = eproc_fsm:send_create_event(?MODULE, {}, reset, CreateOpts),
    {ok, FsmRef}.


reset(FsmRef) ->
    eproc_fsm:send_event(resolve_ref(FsmRef), reset).

skip(FsmRef) ->
    eproc_fsm:send_event(resolve_ref(FsmRef), skip).

close(FsmRef) ->
    eproc_fsm:send_event(resolve_ref(FsmRef), close).

next(FsmRef) ->
    eproc_fsm:sync_send_event(resolve_ref(FsmRef), next).

get(FsmRef) ->
    eproc_fsm:sync_send_event(resolve_ref(FsmRef), get).

last(FsmRef) ->
    eproc_fsm:sync_send_event(resolve_ref(FsmRef), last).

flip(FsmRef) ->
    eproc_fsm:send_event(resolve_ref(FsmRef), flip).

exists(FsmRef) ->
    eproc_fsm:is_online(resolve_ref(FsmRef)).



%% =============================================================================
%%  Internal data structures.
%% =============================================================================

-record(state, {
    seq :: integer()
}).



%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, #state{seq = undefined}}.


%%
%%  Runtime init.
%%
init(_StateName, _StateData) ->
    ok.


%%
%%  The initial state.
%%
handle_state([], {event, reset}, StateData) ->
    {next_state, [incrementing], StateData#state{seq = 0}};

handle_state([], {sync, From, get}, StateData) ->
    ok = eproc_fsm:reply(From, 0),
    {next_state, [incrementing], StateData#state{seq = 0}};


%%
%%  The `incrementing` state.
%%
handle_state([incrementing], {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state([incrementing], {event, reset}, StateData) ->
    {next_state, [incrementing], StateData#state{seq = 0}};

handle_state([incrementing], {event, flip}, StateData) ->
    {next_state, [decrementing], StateData};

handle_state([incrementing], {event, skip}, StateData = #state{seq = Seq}) ->
    {same_state, StateData#state{seq = Seq + 1}};

handle_state([incrementing], {event, close}, StateData) ->
    {final_state, [closed], StateData};

handle_state([incrementing], {sync, _From, next}, StateData = #state{seq = Seq}) ->
    {reply_next, {ok, Seq + 1}, [incrementing], StateData#state{seq = Seq + 1}};

handle_state([incrementing], {sync, _From, get}, StateData = #state{seq = Seq}) ->
    {reply_same, {ok, Seq}, StateData};

handle_state([incrementing], {sync, _From, last}, StateData = #state{seq = Seq}) ->
    {reply_final, {ok, Seq}, [closed], StateData};

handle_state([incrementing], {exit, _NextState}, StateData) ->
    {ok, StateData};


%%
%%  The `decrementing` state.
%%
handle_state([decrementing], {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state([decrementing], {event, reset}, StateData) ->
    {next_state, [decrementing], StateData#state{seq = 0}};

handle_state([decrementing], {event, flip}, StateData) ->
    {next_state, [incrementing], StateData};

handle_state([decrementing], {event, skip}, StateData = #state{seq = Seq}) ->
    {same_state, StateData#state{seq = Seq - 1}};

handle_state([decrementing], {event, close}, StateData) ->
    {final_state, [closed], StateData};

handle_state([decrementing], {sync, _From, next}, StateData = #state{seq = Seq}) ->
    {reply_next, {ok, Seq - 1}, [decrementing], StateData#state{seq = Seq - 1}};

handle_state([decrementing], {sync, _From, get}, StateData = #state{seq = Seq}) ->
    {reply_same, {ok, Seq}, StateData};

handle_state([decrementing], {sync, _From, last}, StateData = #state{seq = Seq}) ->
    {reply_final, {ok, Seq}, [closed], StateData};

handle_state([decrementing], {exit, _NextState}, StateData) ->
    {ok, StateData}.


%%
%%
%%
terminate(_Reason, _StateName, _StateData) ->
    ok.


%%
%%
%%
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


%%
%%
%%
format_status(_Opt, State) ->
    State.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Only needed to use iid and name without using {name, ...} in the client.
%%
resolve_ref({inst, IID}) -> {inst, IID};
resolve_ref(Name)        -> {name, Name}.

