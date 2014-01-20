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
%%  Supervises FSM instances.
%%
-module(eproc_fsm_sup).
-behaviour(supervisor).
-compile([{parse_transform, lager_transform}]).
-export([start_link/0, start_instance/2]).
-export([init/1]).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Start this supervisor.
%%
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, {}).


%%
%%  Starts new `eproc_fsm` instance.
%%
start_instance(InstId, Options) ->
    supervisor:start_child(?MODULE, [InstId, Options]).



%% =============================================================================
%%  Callbacks for `supervisor`.
%% =============================================================================

%%
%%  Supervisor configuration.
%%
init({}) ->
    {ok, {{simple_one_for_one, 100, 10}, [
        {eproc_fsm, {eproc_fsm, start_link, []}, transient, 10000, worker, [eproc_fsm]}
    ]}}.


