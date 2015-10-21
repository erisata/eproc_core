%%%
%%% Implementation of the SNMP metrics, as described in the `mibs/ERISATA-EPROC-MIB.mib`.
%%%
-module(eproc_snmp).
-export([
    ot_engine_name/1,
    ot_inst_stats/2,
    ot_trans_stats/2,
    ot_msg_stats/2
]).

-define(ANY, '_').


%%
%%
%%
ot_engine_name(get) ->
    {value, erlang:atom_to_list(node())}.


%%
%%
%%
ot_inst_stats(get, Type) ->
    {value, eproc_stats:get_value(inst, ?ANY, Type)}.


%%
%%
%%
ot_trans_stats(get, Type) ->
    {value, eproc_stats:get_value(trans, ?ANY, Type)}.


%%
%%
%%
ot_msg_stats(get, Type) ->
    {value, eproc_stats:get_value(msg, ?ANY, Type)}.


