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

%%
%%  Process with alternating states, which can register router keys.
%%

-module(eproc_fsm__router_key).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([new/0, add_key/4, add_keys/2, next_state/1, finalise/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include_lib("eproc_core/include/eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Start unnamed process.
%%  This function uses sync create event.
%%
new() ->
    lager:debug("Creating new ROUTER KEY FSM."),
    StartOpts = [{register, id}],
    CreateOpts = [{start_spec, {default, StartOpts}}],
    {ok, FsmRef, ok} = eproc_fsm:sync_send_create_event(?MODULE, {}, start, CreateOpts),
    {ok, FsmRef}.


%%
%%  Add key for this instance
%%
add_key(FsmRef, Key, Scope, Opts) ->
    [Result] = eproc_fsm:sync_send_event(FsmRef, {add_keys, [{Key, Scope, Opts}]}),
    Result.


%%
%%  Add several keys in one transition for this instance
%%  KeyList :: [{Key, Scope, Opts}]
%%
add_keys(FsmRef, KeyList) ->
    eproc_fsm:sync_send_event(FsmRef, {add_keys, KeyList}).


%%
%%  Flip state of this instance:
%%      * {active, one} to {active, two};
%%      * {active, two} to {active, one}.
%%
next_state(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, next_state).


%%
%%  Stop this instance
%%
finalise(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, finalise).


%% =============================================================================
%%  Internal data structures.
%% =============================================================================


-record(state, {}).


%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, initial, #state{}}.


%%
%%  Runtime init.
%%
init(_StateName, _StateData) ->
    ok.


%%
%%  The initial state.
%%
handle_state(initial, {sync, _From, start}, StateData) ->
    {reply_next, ok, active, StateData};


%%
%%  The `active` state.
%%
handle_state(active, {entry, _PrevState}, StateData) ->
    {next_state, {active, one}, StateData};

handle_state({active, _}, {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state({active, _}, {sync, _From, {add_keys, KeyList}}, StateData) ->
    AddKeyFun = fun({Key, Scope, Opts}) ->
        case eproc_router:add_key(Key, Scope, Opts) of
            ok              -> {ok, eproc_router:lookup(Key)};
            {error, Reason} -> {error, Reason}
        end
    end,
    Reply = lists:map(AddKeyFun, KeyList),
    {reply_same, Reply, StateData};

handle_state({active, _}, {sync, _From, finalise}, StateData) ->
    {reply_final, ok, done, StateData};

handle_state({active, _}, {exit, _NextState}, StateData) ->
    {ok, StateData};


%%
%%  The `active,one` state.
%%
handle_state({active, one}, {sync, _From, next_state}, StateData) ->
    {reply_next, ok, {active, two}, StateData};


%%
%%  The `active,two` state.
%%
handle_state({active, two}, {sync, _From, next_state}, StateData) ->
    {reply_next, ok, {active, one}, StateData}.


%%
%%
%%
terminate(_Reason, _StateName, _StateData) ->
    ok.


%%
%%
%%
code_change(_OldVsn, StateName, StateData = #state{}, _Extra) ->
    {ok, StateName, StateData}.


%%
%%
%%
format_status(_Opt, State) ->
    State.



