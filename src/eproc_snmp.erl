%/--------------------------------------------------------------------
%| Copyright 2015-2016 Erisata, UAB (Ltd.)
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
%%% Implementation of the SNMP metrics, as described in the `mibs/ERISATA-EPROC-MIB.mib`.
%%%
-module(eproc_snmp).
-export([
    ot_store_module/1,
    ot_registry_module/1,
    ot_limit_count/1,
    ot_inst_stats/2,
    ot_trn_stats/2,
    ot_msg_stats/2,
    ot_store_stats/3
]).

-define(ANY, '_').

%%
%%
%%
ot_store_module(get) ->
    {ok, {Module, _Function, _Args}} = eproc_core_app:store_cfg(),
    {value, erlang:atom_to_list(Module)}.


%%
%%
%%
ot_registry_module(get) ->
    case eproc_core_app:registry_cfg() of
        {ok, {Module, _Function, _Args}} ->
            {value, erlang:atom_to_list(Module)};
        undefined ->
            {value, ""}
    end.


%%
%%
%%
ot_limit_count(get) ->
    {value, eproc_limits:info(count)}.


%%
%%
%%
ot_inst_stats(get, StatType) ->
    {value, eproc_stats:get_fsm_stats(inst, ?ANY, StatType)}.


%%
%%
%%
ot_trn_stats(get, StatType) ->
    {value, eproc_stats:get_fsm_stats(trn, ?ANY, StatType)}.


%%
%%
%%
ot_msg_stats(get, StatType) ->
    {value, eproc_stats:get_fsm_stats(msg, ?ANY, StatType)}.


%%
%%
%%
ot_store_stats(get, Operation, StatType) ->
    {value, eproc_stats:get_store_stats(Operation, StatType)}.


