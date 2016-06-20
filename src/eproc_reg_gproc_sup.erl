%/--------------------------------------------------------------------
%| Copyright 2013-2016 Erisata, UAB (Ltd.)
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

%%%
%%% Supervisor for the `eproc_reg_gproc`.
%%%
-module(eproc_reg_gproc_sup).
-behaviour(supervisor).
-export([start_link/5, reset/1]).
-export([init/1]).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%  Create this supervisor.
%%
start_link(RegistryArgs, SupName, SupDefName, SupMfaName, MgrName) ->
    supervisor:start_link({local, SupName}, ?MODULE, {RegistryArgs, SupDefName, SupMfaName, MgrName}).


%%
%%  Restart the children.
%%
reset(SupName) ->
    ok = supervisor:terminate_child(SupName, {eproc_reg_gproc, sup_def}),
    ok = supervisor:terminate_child(SupName, {eproc_reg_gproc, sup_mfa}),
    ok = supervisor:terminate_child(SupName, {eproc_reg_gproc, manager}),
    {ok, _ChildSupDef } = supervisor:restart_child(SupName, {eproc_reg_gproc, sup_def}),
    {ok, _ChildSupMfa } = supervisor:restart_child(SupName, {eproc_reg_gproc, sup_mfa}),
    {ok, _ChildManager} = supervisor:restart_child(SupName, {eproc_reg_gproc, manager}),
    ok.



%%% ============================================================================
%%% Callbacks for supervisor.
%%% ============================================================================

%%
%%  Supervisor initialization.
%%
init({RegistryArgs, SupDefName, SupMfaName, MgrName}) ->
    Load = proplists:get_value(load, RegistryArgs, true),
    Reg    = eproc_reg_gproc,
    SupDef = eproc_fsm_def_sup,
    SupMfa = eproc_fsm_mfa_sup,
    DefSpec = {{Reg, sup_def}, {SupDef, start_link, [{local, SupDefName}]}, permanent, 10000, supervisor, [SupDef]},
    MfaSpec = {{Reg, sup_mfa}, {SupMfa, start_link, [{local, SupMfaName}]}, permanent, 10000, supervisor, [SupMfa]},
    MgrSpec = {{Reg, manager}, {Reg,    start_link, [{local, MgrName}, Load]}, permanent, 10000, worker, [Reg]},
    {ok, {{one_for_all, 100, 10},
        [DefSpec, MfaSpec, MgrSpec]
    }}.


