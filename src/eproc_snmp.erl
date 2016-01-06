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
    ot_msg_stats/2
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
    {value, eproc_stats:get_value(inst, ?ANY, StatType)}.


%%
%%
%%
ot_trn_stats(get, StatType) ->
    {value, eproc_stats:get_value(trn, ?ANY, StatType)}.


%%
%%
%%
ot_msg_stats(get, StatType) ->
    {value, eproc_stats:get_value(msg, ?ANY, StatType)}.


