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
%%  FSM instance supervisor, starting FSMs using specified function.
%%  This supervisor uses `one_for_one` strategy for managing processes.
%%
-module(eproc_fsm_mfa_sup).
-behaviour(supervisor).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1, start_fsm/3]).
-export([init/1]).
-include("eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Start this supervisor.
%%
-spec start_link(
        Name :: otp_name()
    ) ->
        pid() | {error, term()} | term().

start_link(Name) ->
    supervisor:start_link(Name, ?MODULE, {}).


%%
%%  Starts new `eproc_fsm` instance using the provided function.
%%
-spec start_fsm(
        Supervisor  :: otp_ref(),
        FsmRef      :: fsm_ref(),
        StartMFA    :: {module(), atom(), list()}
    ) ->
        {ok, pid()}.

start_fsm(Supervisor, FsmRef, StartMFA = {Module, _, _}) ->
    Spec = {FsmRef, StartMFA, transient, 10000, worker, [eproc_fsm, Module]},
    {ok, _Pid} = supervisor:start_child(Supervisor, Spec).


%% =============================================================================
%%  Callbacks for `supervisor`.
%% =============================================================================

%%
%%  Supervisor configuration.
%%
init({}) ->
    {ok, {{one_for_one, 100, 10}, []}}.
