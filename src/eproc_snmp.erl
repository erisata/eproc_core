%%%
%%% Implementation of the SNMP metrics, as described in the `mibs/ERISATA-EPROC-MIB.mib`.
%%%
-module(eproc_snmp).
-export([
    ot_engine_name/1,
    ot_inst_count/1,
    ot_inst_errors/1,
    ot_inst_duration/1,
    ot_trans_count/1,
    ot_msg_count/1
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
ot_inst_count(get) ->
    {value, eproc_stats:get_value(inst, ?ANY, count)}.


%%
%%
%%
ot_inst_errors(get) ->
    {value, eproc_stats:get_value(inst, ?ANY, err)}.


%%
%%
%%
ot_inst_duration(get) ->
    {value, eproc_stats:get_value(inst, ?ANY, dur)}.


%%
%%
%%
ot_trans_count(get) ->
    {value, eproc_stats:get_value(trans, ?ANY, count)}.


%%
%%
%%
ot_msg_count(get) ->
    {value, eproc_stats:get_value(msg, ?ANY, count)}.


