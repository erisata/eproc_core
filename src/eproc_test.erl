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

%%%
%%% This module is helpful for testing FSM implementations.
%%%
-module(eproc_test).
-export([get_state/1, wait_term/1, wait_term/2]).
-include("eproc.hrl").

-define(WAIT_TERM_REPEAT, 10).
-define(WAIT_TERM_TIMEOUT, {1,s}).
-define(WAIT_TERM_MAX_INSTANCES, 100).

%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%% Function return instance status and state name.
%%
-spec get_state(FsmRef :: fsm_ref()) -> {ok, Status :: inst_status(), StateName :: term(), StateData :: term()}.

get_state(FsmRef) ->
    FilterClause = case FsmRef of
        {inst, InstId} -> {id, InstId};
        {name, Name}   -> {name, Name}
    end,
    {ok, {1, _, [Instance]}} = eproc_store:get_instance(undefined, {filter, {1, 2}, [FilterClause]}, current),
    #instance{status = Status, curr_state = #inst_state{sname = StateName, sdata = StateData}} = Instance,
    {ok, Status, StateName, StateData}.


%%
%% Function returns, when every instance, refered by Filters, is terminated,
%% but no later than the defined timeout.
%% No more than ?WAIT_FOR_COMPLETION_MAX_INSTANCES are checked.
%% Elements of Filters are of the same type, as specified in eproc_store:get_instance/3 FilterClause type.
%%
-spec wait_term(Filters :: list()) -> ok | {error, timeout}.

wait_term(Filters) ->
    wait_term(Filters, ?WAIT_TERM_TIMEOUT).

-spec wait_term(Filters :: list(), Timeout :: duration()) -> ok | {error, timeout}.

wait_term(Filters, Timeout) ->
    StopAt = eproc_timer:timestamp_after(Timeout, os:timestamp()),
    FilterTuple = {filter, {1,?WAIT_TERM_MAX_INSTANCES}, Filters},
    {ok, {_, _, Instances}} = eproc_store:get_instance(undefined, FilterTuple, header),
    GetInstIdFun = fun(#instance{inst_id = InstId}) -> {inst, InstId} end,
    InstIds = lists:map(GetInstIdFun, Instances),
    wait_term2(InstIds, StopAt).


%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

wait_term2(InstIds, StopAt) ->
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
                    timer:sleep(?WAIT_TERM_REPEAT),
                    wait_term2([Id | Ids], StopAt)
            end;
        false ->
            {error, timeout}
    end.


