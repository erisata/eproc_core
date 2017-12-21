%/--------------------------------------------------------------------
%| Copyright 2013-2017 Erisata, UAB (Ltd.)
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

%%% @doc
%%% Main API for the `eproc' application.
%%%
-module(eproc).
-compile([{parse_transform, lager_transform}]).
-export([now/0]).
-export([instance_state/2]).
-include("eproc.hrl").


%%  @doc
%%  Returns current time, consistelly for the entire system.
%%  TODO: Move to some othe module.
%%
-spec now() -> timestamp().

now() ->
    os:timestamp().


%%  @doc
%%  Get current state of the specified instance.
%%
%%  By defauls, this function returns the state, that can be out-of-sync
%%  with the running instance, as it is retrieved from the data store.
%%  This is done to avoid locking and interferece with the runtime.
%%
%%  This function is intended to be called from the FSM implementation
%%  module in order to have access to the state record.
%%
-spec instance_state(
        FsmRef      :: fsm_ref(),
        Opts        :: #{}
    ) ->
        {ok,
            Status :: inst_status(),
            SName  :: term(),
            SData  :: term()
        } |
        {error, Reason :: term()}.

instance_state(FsmRef, _Opts) ->
    case eproc_store:get_instance(undefined, FsmRef, current) of
        {ok, #instance{status = Status, curr_state = #inst_state{sname = SName, sdata = SData}}} ->
            {ok, Status, SName, SData};
        {error, Reason} ->
            {error, Reason}
    end.


