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
%%% Collects and provides runtime statictics.
%%% Implemented using Exometer.
%%%
-module(eproc_stats).
-compile([{parse_transform, lager_transform}]).
-export([
    i/0,
    info/1,
    reset/1,
    setup/0,
    add_instance_created/1,
    add_instance_started/1,
    add_instance_suspended/1,
    add_instance_resumed/1,
    add_instance_killed/2,
    add_instance_completed/2,
    add_instance_crashed/1,
    add_transition_completed/6,
    get_fsm_stats/3,
    add_store_operation/2,
    get_store_stats/2
]).

-define(ROOT, eproc_core).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%
%%  Print main statistics.
%%
i() ->
    info(list).


%%
%%  Return statistics by the specified query.
%%
info(list) ->
    Entries = exometer:find_entries([?ROOT]),
    {ok, [ Name || {Name, _Type, enabled} <- Entries ]}.


%%
%%  Reset statistic counters.
%%  This function is mainly usefull for testing.
%%
reset(all) ->
    Entries = exometer:find_entries([?ROOT]),
    [ ok = exometer:reset(Name) || {Name, _Type, enabled} <- Entries ],
    ok.


%%
%%  Create static metrics.
%%
setup() ->
    ok = exometer:ensure([?ROOT, store, get_instance],          uniform, []),
    ok = exometer:ensure([?ROOT, store, get_transition],        uniform, []),
    ok = exometer:ensure([?ROOT, store, get_state],             uniform, []),
    ok = exometer:ensure([?ROOT, store, get_message],           uniform, []),
    ok = exometer:ensure([?ROOT, store, get_node],              uniform, []),
    ok = exometer:ensure([?ROOT, store, add_instance],          uniform, []),
    ok = exometer:ensure([?ROOT, store, add_transition],        uniform, []),
    ok = exometer:ensure([?ROOT, store, set_instance_killed],   uniform, []),
    ok = exometer:ensure([?ROOT, store, set_instance_suspended], uniform, []),
    ok = exometer:ensure([?ROOT, store, set_instance_resuming], uniform, []),
    ok = exometer:ensure([?ROOT, store, set_instance_resumed],  uniform, []),
    ok = exometer:ensure([?ROOT, store, add_inst_crash],        uniform, []),
    ok = exometer:ensure([?ROOT, store, load_instance],         uniform, []),
    ok = exometer:ensure([?ROOT, store, load_running],          uniform, []),
    ok = exometer:ensure([?ROOT, store, attr_task],             uniform, []),
    ok = exometer:ensure([?ROOT, store, attachment_save],       uniform, []),
    ok = exometer:ensure([?ROOT, store, attachment_read],       uniform, []),
    ok = exometer:ensure([?ROOT, store, attachment_delete],     uniform, []),
    ok = exometer:ensure([?ROOT, store, attachment_cleanup],    uniform, []),
    ok.


%%
%%  Records the instance created events.
%%
add_instance_created(InstType) ->
    ok = inc_spiral([?ROOT, inst, InstType, created]).


%%
%%  Records the instance started events.
%%
add_instance_started(InstType) ->
    ok = inc_spiral([?ROOT, inst, InstType, started]).


%%
%%  Records the instance suspend events.
%%
add_instance_suspended(InstType) ->
    ok = inc_spiral([?ROOT, inst, InstType, suspended]).


%%
%%  Records the instace resumes.
%%
add_instance_resumed(InstType) ->
    ok = inc_spiral([?ROOT, inst, InstType, resumed]).


%%
%%  Records the instance kill events.
%%
add_instance_killed(InstType, Created) ->
    DurationUS = get_duration(Created),
    ok =    inc_spiral([?ROOT, inst, InstType, killed]),
    ok = update_spiral([?ROOT, inst, InstType, duration], DurationUS).


%%
%%  Records instance successfull completion events.
%%
add_instance_completed(InstType, Created) ->
    DurationUS = get_duration(Created),
    ok =    inc_spiral([?ROOT, inst, InstType, completed]),
    ok = update_spiral([?ROOT, inst, InstType, duration], DurationUS).


%%
%%  Records instance crashes.
%%
add_instance_crashed(InstType) ->
    ok = inc_spiral([?ROOT, inst, InstType, crashed]).


%%
%%  Records transitions made by the instances of particular type.
%%
add_transition_completed(InstType, DurationUS, _ReqMsgType, HadReplyMsg, OutMsgAsync, OutMsgSync) ->
    ok = inc_spiral([?ROOT, trn, InstType, count]),
    ok = update_spiral([?ROOT, trn, InstType, duration], DurationUS),
    case HadReplyMsg of
        false -> ok = inc_spiral([?ROOT, msg, InstType, in_async]);
        true  -> ok = inc_spiral([?ROOT, msg, InstType, in_sync])
    end,
    ok = update_spiral([?ROOT, msg, InstType, out_async], OutMsgAsync),
    ok = update_spiral([?ROOT, msg, InstType, out_sync], OutMsgSync),
    ok.


%%
%%
%%
get_fsm_stats(Object, InstType, StatType) ->
    get_value_spiral([?ROOT, Object, InstType, StatType]).



%%
%%  Records duration of the store operations.
%%
add_store_operation(Operation, DurationUS) ->
    ok = exometer:update([?ROOT, store, Operation], DurationUS).


%%
%%  Returns specific statictic for the particular store peration.
%%
get_store_stats(Operation, DataPoint) ->
    {ok, [{DataPoint, Value}]} = exometer:get_value([?ROOT, store, Operation], DataPoint),
    Value.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%
%%
inc_spiral(Name) ->
    ok = exometer:update_or_create(Name, 1, spiral, []).


%%
%%
%%
update_spiral(Name, Value) ->
    ok = exometer:update_or_create(Name, Value, spiral, []).


%%
%%
%%
get_optional(Name, DataPoint) ->
    case exometer:get_value(Name, DataPoint) of
        {ok, [{DataPoint, Val}]} -> Val;
        {error, not_found} -> 0
    end.


%%
%%
%%
get_value_spiral(MatchHead) ->
    Entries = exometer:find_entries(MatchHead),
    lists:foldr(fun({Name, _Type, _Status}, Acc) ->
        Acc + get_optional(Name, one)
    end, 0, Entries).


%%
%%
%%
get_duration(Created) ->
    Now = erlang:timestamp(),
    eproc_timer:timestamp_diff_us(Now, Created).


