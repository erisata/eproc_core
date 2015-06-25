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

%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%% Function return instance status and state data.
%%
-spec get_states(FsmRef :: fsm_ref()) -> {ok, Status :: inst_status(), StateData :: term()}.

get_states(FsmRef) ->
    {ok, #instance{status = Status, curr_state = State}} = eproc_store:get_instance(undefined, FsmRef, current),
    #inst_state{sdata = StateData} = State,
    {ok, Status, StateData}.


%%
%% Function returns, when the instance is terminated, but no later than the defined timeout.
%%
-spec wait_for_completion(FsmRef :: fsm_ref()) -> ok | {error, time_out}.

wait_for_completion(FsmRef) ->
    wait_for_completion(FsmRef, ?WAIT_FOR_COMPLETION_TIMEOUT).

-spec wait_for_completion(FsmRef :: fsm_ref(), Timeout :: duration()) -> ok | {error, time_out}.

wait_for_completion(FsmRef, Timeout) ->
    StopAt = eproc_timer:timestamp_after(Timeout, erlang:now()),
    wait_for_completion2(FsmRef, StopAt).


%% =============================================================================
%%  Internal functions.
%% =============================================================================

wait_for_completion2(FsmRef, StopAt) ->
    case erlang:now() < StopAt of
        true ->
            {ok, #instance{status = Status}} = eproc_store:get_instance(undefined, FsmRef, header),
            case Status of
                completed   -> ok;
                killed      -> ok;
                failed      -> ok;
                _           ->
                    timer:sleep(?WAIT_FOR_COMPLETION_REPEAT),
                    wait_for_completion2(FsmRef, StopAt)
            end;
        false ->
            {error, time_out}
    end.


