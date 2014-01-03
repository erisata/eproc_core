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
%%  OTP Application module for eproc.
%%
%%  The following options can/should be provided for the
%%  `eproc_core` application:
%%
%%  `store`
%%  :   [mandatory] specifies store implementation to be used.
%%  `registry`
%%  :   [mandatory] specifies registry implementation to be used.
%%
-module(eproc_core_app).
-behaviour(application).
-export([start/2, stop/1]).

-define(APP, eproc_core).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  TODO: Use this function in eproc_store.
%%
store() ->
    {ok, _Store} = application:get_env(?APP, store).


%%
%%  TODO: Use this function in eproc_registry.
%%
registry() ->
    {ok, _Registry} = application:get_env(?APP, registry).



%% =============================================================================
%%  Application callbacks
%% =============================================================================


%%
%% Start the application.
%%
start(_StartType, _StartArgs) ->
    ok = validate_env(application:get_all_env()),
    {ok, Store} = store(),
    {ok, Registry} = registry(),
    eproc_core_sup:start_link(Store, Registry).


%%
%% Stop the application.
%%
stop(_State) ->
    ok.



%% =============================================================================
%%  Helper functions.
%% =============================================================================

%%
%%  Checks if application environment is valid.
%%
validate_env(Env) ->
    ok = validate_env_mandatory(store, Env, "The 'store' parameter is mandatory"),
    ok = validate_env_mandatory(registry, Env, "The 'registry' parameter is mandatory").


%%
%%  Checks if mandatory key is presented in the application env.
%%
validate_env_mandatory(Key, Env, Message) ->
    case proplists:lookup(Key, Env) of
        none -> {error, Message};
        {Key, _} -> ok
    end.

