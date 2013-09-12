%/--------------------------------------------------------------------
%| Copyright 2013 Karolis Petrauskas
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
%%  Main behaviour to be implemented by a user of the `eproc`.
%%
%%  This module designed by taking into account UML FSM definition
%%  as well as the Erlang/OTP `gen_fsm`. The following is the list
%%  of differences comparing it to `gen_fsm`:
%%
%%    * State name supports substates and orthogonal states.
%%    * Callback `Module:handle_state/4` is used instead of `Module:StateName/2-3`.
%%    * Process configuration is passed as a separate argument to the fsm.
%%    * Has support for state entry and exit actions.
%%    * Has support for scopes. The scopes can be used to manage timers and keys.
%%    * Supports automatic state persistence.
%%
-module(eproc_fsm).
%-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/3, call/2, cast/2, kill/2, suspend/2, resume/2, set_state/4]).
-export([reply/2]).
-export_type([inst_id/0, inst_ref/0]).
-include("eproc.hrl").


-record(inst_ref, {
}).

-opaque inst_id()   :: integer().
-opaque inst_ref()  :: #inst_ref{}.
-type state_event() :: term().
-type state_name()  :: list().
-type state_data()  :: term().
-type state_action() :: term().
-type state_phase() :: event | entry | exit.


%% =============================================================================
%%  Callback definitions.
%% =============================================================================


%%
%%
%%
-callback init(
        #definition{},
        state_event(),
        inst_ref()
    ) ->
    {ok, state_name(), state_data()} |
    {ok, state_name(), state_data(), [state_action()]}.


%%
%%
%%
-callback handle_state(
        state_name(),
        state_phase(),
        state_event() | state_name(),
        state_data(),
        inst_ref()
    ) ->
    {same_state, state_data()} |
    {same_state, state_data(), [state_action()]} |
    {next_state, state_name(), state_data()} |
    {next_state, state_name(), state_data(), [state_action()]} |
    {final_state, state_name(), state_data()}.


%%
%%
%%
-callback handle_status(
    state_name(),
    state_data(),
    Query           :: atom(),
    MediaType       :: atom()
    ) ->
    {ok, MediaType :: atom(), Status :: binary() | term()} |
    {error, Reason :: term()}.


%%
%%
%%
-callback state_change(
    OldStateData    :: state_data(),
    InstRef         :: inst_ref()
    ) ->
    {ok, NewStateData :: state_data()}.



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
-spec start_link(inst_id(), #definition{}, store_ref()) -> ok.

start_link(_InstanceId, _Definition, _StoreRef) ->
    ok.


%%
%%
%%
call(_InstanceId, _Event) ->
    ok.


%%
%%
%%
cast(_InstanceId, _Event) ->
    ok.


%%
%%
%%
kill(_InstanceId, _Reason) ->
    ok.


%%
%%
%%
suspend(_InstanceId, _Reason) ->
    ok.


%%
%%
%%
resume(_InstanceId, _Reason) ->
    ok.


%%
%%
%%
set_state(_InstanceId, _NewStateName, _NewStateData, _Reason) ->
    ok.


%%
%%  To be used by the process implementation to sent response to a synchronous
%%  request before the `handle_state/4` function completes.
%%
-spec reply(state_event(), inst_ref()) -> ok.

reply(_Response, _InstRef) ->
    ok.


%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================



%% =============================================================================
%%  Internal functions.
%% =============================================================================


