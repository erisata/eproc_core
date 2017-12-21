%/--------------------------------------------------------------------
%| Copyright 2013-2017 Erisata, UAB (Ltd.)
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

%%% @doc
%%% Sequence-generating process for testing `eproc_fsm'. Terminates never.
%%% The states are the following:
%%%
%%%     [] --- reset ---> incrementing --- flip ---> decrementing.
%%%
-module(eproc_fsm__seq).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([new/0, named/1, reset/1, skip/1, close/1, next/1, get/1, last/1, flip/1, exists/1, state/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include_lib("eproc_core/include/eproc.hrl").


%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

-record(data, {
    seq :: integer()
}).



%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  Start unnamed seq.
%%  This function uses sync create event.
%%
new() ->
    lager:debug("Creating new SEQ."),
    StartOpts = [{register, id}],
    CreateOpts = [{start_spec, {default, StartOpts}}],
    {ok, FsmRef, 0} = eproc_fsm:sync_send_create_event(?MODULE, {}, get, CreateOpts),
    {ok, FsmRef}.


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
    EventTypeFun = fun (event, close) ->
        {<<"CLOSE">>, <<"IMMEDIATELLY!">>}
    end,
    eproc_fsm:send_event(resolve_ref(FsmRef), close, [{type, EventTypeFun}]).

next(FsmRef) ->
    eproc_fsm:sync_send_event(resolve_ref(FsmRef), next).

get(FsmRef) ->
    eproc_fsm:sync_send_event(resolve_ref(FsmRef), get, [{type, what}]).

last(FsmRef) ->
    eproc_fsm:sync_send_event(resolve_ref(FsmRef), last).

flip(FsmRef) ->
    eproc_fsm:send_event(resolve_ref(FsmRef), flip).

exists(FsmRef) ->
    eproc_fsm:is_online(resolve_ref(FsmRef)).

state(FsmRef) ->
    {ok, Status, State, #data{seq = Seq}} = eproc:instance_state(FsmRef, #{}),
    {ok, Status, State, Seq}.



%%% ============================================================================
%%% Callbacks for eproc_fsm.
%%% ============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, #data{seq = undefined}}.


%%
%%  Runtime init.
%%
init(_State, _Data) ->
    ok.


%%
%%  The initial state.
%%
handle_state({}, {event, reset}, Data) ->
    {next_state, incrementing, Data#data{seq = 0}};

handle_state({}, {sync, From, get}, Data) ->
    ok = eproc_fsm:reply(From, 0),
    {next_state, incrementing, Data#data{seq = 0}};


%%
%%  The `incrementing' state.
%%
handle_state(incrementing, {entry, _PrevState}, Data) ->
    {ok, Data};

handle_state(incrementing, {event, reset}, Data) ->
    {next_state, incrementing, Data#data{seq = 0}};

handle_state(incrementing, {event, flip}, Data) ->
    {next_state, decrementing, Data};

handle_state(incrementing, {event, skip}, Data = #data{seq = Seq}) ->
    {same_state, Data#data{seq = Seq + 1}};

handle_state(incrementing, {event, close}, Data) ->
    {final_state, closed, Data};

handle_state(incrementing, {sync, _From, next}, Data = #data{seq = Seq}) ->
    {reply_next, {ok, Seq + 1}, incrementing, Data#data{seq = Seq + 1}};

handle_state(incrementing, {sync, _From, get}, Data = #data{seq = Seq}) ->
    {reply_same, {ok, Seq}, Data};

handle_state(incrementing, {sync, _From, last}, Data = #data{seq = Seq}) ->
    {reply_final, {ok, Seq}, closed, Data};

handle_state(incrementing, {exit, _NextState}, Data) ->
    {ok, Data};


%%
%%  The `decrementing' state.
%%
handle_state(decrementing, {entry, _PrevState}, Data) ->
    {ok, Data};

handle_state(decrementing, {event, reset}, Data) ->
    {next_state, decrementing, Data#data{seq = 0}};

handle_state(decrementing, {event, flip}, Data) ->
    {next_state, incrementing, Data};

handle_state(decrementing, {event, skip}, Data = #data{seq = Seq}) ->
    {same_state, Data#data{seq = Seq - 1}};

handle_state(decrementing, {event, close}, Data) ->
    {final_state, closed, Data};

handle_state(decrementing, {sync, _From, next}, Data = #data{seq = Seq}) ->
    {reply_next, {ok, Seq - 1}, decrementing, Data#data{seq = Seq - 1}};

handle_state(decrementing, {sync, _From, get}, Data = #data{seq = Seq}) ->
    {reply_same, {ok, Seq}, Data};

handle_state(decrementing, {sync, _From, last}, Data = #data{seq = Seq}) ->
    {reply_final, {ok, Seq}, closed, Data};

handle_state(decrementing, {exit, _NextState}, Data) ->
    {ok, Data}.


%%
%%
%%
terminate(_Reason, _State, _Data) ->
    ok.


%%
%%
%%
code_change(_OldVsn, State, Data = #data{}, _Extra) ->
    {ok, State, Data}.


%%
%%
%%
format_status(_Opt, State) ->
    State.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%  Only needed to use iid and name without using {name, ...} in the client.
%%
resolve_ref({inst, IID}) -> {inst, IID};
resolve_ref(Name)        -> {name, Name}.


