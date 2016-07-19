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
%%  Example FSM implementation, that uses `eproc_meta`.
%%
%%  States:
%%
%%    * {}     --create--> open
%%    * open   --close---> closed
%%    * closed --          final
%%
-module(eproc_fsm__inquiry).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([create/2, close/2]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include_lib("eproc_core/include/eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Create new inquiry.
%%
create(CustNr, Inquiry) ->
    StartOpts = [
        {register, id},
        {start_sync, {eproc_registry, wait_for, [undefined, all_started, 60000]}}
    ],
    CreateOpts = [{start_spec, {default, StartOpts}}],
    {ok, _FsmRef} = eproc_fsm:send_create_event(?MODULE, {}, {create, CustNr, Inquiry}, CreateOpts).


%%
%%  Close the inquiry.
%%
close(FsmRef, Resolution) ->
    eproc_fsm:sync_send_event(FsmRef, {close, Resolution}).



%% =============================================================================
%%  Internal data structures.
%% =============================================================================

-record(state, {
    cust_nr :: integer(),
    inquiry :: binary()
}).



%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, #state{}}.


%%
%%  Runtime init.
%%
init(_StateName, _StateData) ->
    ok.


%%
%%  The initial state.
%%
handle_state({}, {event, {create, CustNr, Inquiry}}, StateData) ->
    ok = eproc_meta:add_tag(CustNr, cust_nr),
    {next_state, open, StateData#state{cust_nr = CustNr, inquiry = Inquiry}};


%%
%%  The `open` state.
%%
handle_state(open, {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state(open, {sync, _From, {close, Resolution}}, StateData) ->
    ok = eproc_meta:add_tag(Resolution, resolution),
    {reply_final, ok, closed, StateData};

handle_state(open, {exit, _NextState}, StateData) ->
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


