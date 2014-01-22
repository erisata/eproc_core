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
%%  Main supervisor.
%%
-module(eproc_core_sup).
-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).


%% =============================================================================
%% API functions.
%% =============================================================================


%%
%%  Create this supervisor.
%%
start_link() ->
    supervisor:start_link(?MODULE, {}).



%% =============================================================================
%% Callbacks for supervisor.
%% =============================================================================


%%
%%  Supervisor initialization.
%%
init({}) ->
    {ok, {StoreMod, StoreArgs}} = eproc_core_app:store_cfg(),
    StoreSpec = {store,
        {StoreMod, start_link, [StoreArgs]},
        permanent, 10000, worker, [StoreMod, eproc_store]
    },

    RestartSpec = {restart,
        {eproc_restart, start_link, []},
        permanent, 10000, worker, [eproc_restart]
    },

    RegistrySpec = case eproc_core_app:registry_cfg() of
        {ok, {RegistryMod, RegistryArgs}} ->
            [{registry,
                {RegistryMod, start_link, [RegistryArgs]},
                permanent, 10000, worker, [RegistryMod, eproc_registry]
            }];
        undefined ->
            []
    end,

    {ok, {{one_for_all, 100, 10},
        [StoreSpec, RestartSpec] ++ RegistrySpec
    }}.


