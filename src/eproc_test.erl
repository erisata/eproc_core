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
%%  This module is helpful for testinf FSM implementations.
%%
-module(eproc_test).
-export([get_states/1, wait_for_completion/1, wait_for_completion/2]).
-include("eproc.hrl").

-define(WAIT_FOR_COMPLETION_REPEAT, 10).
-define(WAIT_FOR_COMPLETION_TIMEOUT, {1,s}).
-define(WAIT_FOR_COMPLETION_MAX_INSTANCES, 100).

%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%% Function return instance status and state name.
%%
-spec get_states(FsmRef :: fsm_ref()) -> {ok, Status :: inst_status(), StateData :: term()}.

get_states(FsmRef) ->
    FilterClause = case FsmRef of
        {inst, InstId} -> {id, InstId};
        {name, Name}   -> {name, Name}
    end,
    {ok, {1, _, [Instance]}} = eproc_store:get_instance(undefined, {filter, {1, 2}, [FilterClause]}, current),
    #instance{status = Status, curr_state = #inst_state{sname = StateName}} = Instance,
    {ok, Status, StateName}.


%%
%% Function returns, when every instance, refered by Filters, is terminated,
%% but no later than the defined timeout.
%% No more than ?WAIT_FOR_COMPLETION_MAX_INSTANCES are checked.
%% Elements of Filters are of the same type, as specified in eproc_store:get_instance/3 FilterClause type.
%%
-spec wait_for_completion(Filters :: list()) -> ok | {error, time_out}.

wait_for_completion(Filters) ->
    wait_for_completion(Filters, ?WAIT_FOR_COMPLETION_TIMEOUT).

-spec wait_for_completion(Filters :: list(), Timeout :: duration()) -> ok | {error, time_out}.

wait_for_completion(Filters, Timeout) ->
    StopAt = eproc_timer:timestamp_after(Timeout, erlang:now()),
    FilterTuple = {filter, {1,?WAIT_FOR_COMPLETION_MAX_INSTANCES}, Filters},
    {ok, {_, _, Instances}} = eproc_store:get_instance(undefined, FilterTuple, header),
    GetInstIdFun = fun(#instance{inst_id = InstId}) -> {inst, InstId} end,
    InstIds = lists:map(GetInstIdFun, Instances),
    wait_for_completion2(InstIds, StopAt).


%% =============================================================================
%%  Internal functions.
%% =============================================================================

wait_for_completion2(InstIds, StopAt) ->
    case os:timestamp() < StopAt of
        true ->
            {ok, Instances} = eproc_store:get_instance(undefined, {list, InstIds}, header),
            RemoveTerminatedFun = fun
                (#instance{status = completed}) -> false;
                (#instance{status = killed})    -> false;
                (#instance{status = failed})    -> false;
                (#instance{inst_id = InstId})   -> {true, {inst, InstId}}
            end,
            case lists:filtermap(RemoveTerminatedFun, Instances) of
                [] -> ok;
                [Id | Ids] ->
                    timer:sleep(?WAIT_FOR_COMPLETION_REPEAT),
                    wait_for_completion2([Id | Ids], StopAt)
            end;
        false ->
            {error, time_out}
    end.


