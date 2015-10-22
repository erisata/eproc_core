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
%%  OTP Application module for eproc_core.
%%
%%  The following options can/should be provided for the
%%  `eproc_core` application:
%%
%%  `store`
%%  :   [mandatory] specifies store implementation to be used.
%%      Value for this option is MFA, used to get store reference.
%%      Example value: `{eproc_store_ets, ref, []}`.
%%  `registry`
%%  :   [optional] specifies registry implementation to be used.
%%      Value for this option is MFA, used to get registry reference.
%%      Example value: `{eproc_reg_gproc, ref, []}`.
%%
-module(eproc_core_app).
-behaviour(application).
-export([store_cfg/0, registry_cfg/0]).
-export([start/2, stop/1]).

-define(APP, eproc_core).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Get store, as configured in the eproc_core environment.
%%  NOTE: The returned term is not store reference.
%%
-spec store_cfg() -> {ok, term()}.

store_cfg() ->
    {ok, _Store} = application:get_env(?APP, store).


%%
%%  Get registry, as configured in the eproc_core environment.
%%  NOTE: The returned term is not registry reference.
%%
-spec registry_cfg() -> {ok, term()} | undefined.

registry_cfg() ->
    application:get_env(?APP, registry).



%% =============================================================================
%%  Application callbacks
%% =============================================================================


%%
%% Start the application.
%%
start(_StartType, _StartArgs) ->
    ok = validate_env(application:get_all_env()),
    SnmpAgent = enomon_snmp:load_application_mib(?APP, ?MODULE, "ERISATA-EPROC-MIB"),
    {ok, Pid} = eproc_core_sup:start_link(),
    {ok, Pid, {SnmpAgent}}.


%%
%% Stop the application.
%%
stop({SnmpAgent}) ->
    enomon:unload_application_mib(?APP, SnmpAgent, "ERISATA-EPROC-MIB"),
    ok.



%% =============================================================================
%%  Helper functions.
%% =============================================================================

%%
%%  Checks if application environment is valid.
%%
validate_env(Env) ->
    ok = validate_env_mandatory(store, Env, "The 'store' parameter is mandatory").


%%
%%  Checks if mandatory key is presented in the application env.
%%
validate_env_mandatory(Key, Env, Message) ->
    case proplists:lookup(Key, Env) of
        none -> {error, Message};
        {Key, _} -> ok
    end.

