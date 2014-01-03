%/--------------------------------------------------------------------
%| Copyright 2013 Robus, Ltd.
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
%%
%%
-module(eproc_core_sup).
-behaviour(supervisor).
-export([start_link/2]).
-export([init/1]).


%% =============================================================================
%% API functions.
%% =============================================================================


%%
%%  Create this supervisor.
%%
start_link(Store, Registry) ->
    supervisor:start_link(?MODULE, {Store, Registry}).



%% =============================================================================
%% Callbacks for supervisor.
%% =============================================================================


%%
%%  Supervisor initialization.
%%
init({Store, Registry}) ->
    {StoMod, StoArgs} = Store,
    {RegMod, RegArgs} = Registry,
    Specs = [
        {store,    {StoMod, start_link, [StoArgs]}, permanent, 10000, worker, [StoMod, eproc_store]},
        {registry, {RegMod, start_link, [RegArgs]}, permanent, 10000, worker, [RegMod, eproc_registry]}
        % ADD InstSup and InstMgr here?
    ],
    {ok, {{one_for_all, 100, 10}, Specs}}.


