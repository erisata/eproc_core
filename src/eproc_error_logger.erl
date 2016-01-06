%/--------------------------------------------------------------------
%| Copyright 2016 Erisata, UAB (Ltd.)
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
%%% Event handler for the `error_logger`.
%%%
%%% It is used for detecting FSM crashes with sufficient
%%% amount of the context information.
%%%
-module(eproc_error_logger).
-behaviour(gen_event).
-compile([{parse_transform, lager_transform}]).
-export([register/0]).
-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2, code_change/3]).


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%
%%
register() ->
    ok = error_logger:add_report_handler(?MODULE, []).



%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

-record(state, {
}).


%%% ============================================================================
%%% Callbacks for `gen_event`.
%%% ============================================================================

%%
%%
%%
init([]) ->
    {ok, #state{}}.


%%
%%  Handle all the interesting `error_logger` events.
%%
handle_event({error, _GroupLeader, {Pid, _Fmt, [_Name, Msg, InstState, Reason]}}, State) ->
    %
    %   Try to catch messages, reported by `gen_server:error_info/5`.
    %   Some of these reports will mean crash of some EProc FSM processes.
    %
    case eproc_fsm:handle_crash_msg(Pid, Msg, InstState, Reason) of
        ok               -> ok;
        {error, not_fsm} -> ok
    end,
    {ok, State};

handle_event(_Event, State) ->
    {ok, State}.


%%
%%
%%
handle_call(_Request, State) ->
    {ok, undefined, State}.


%%
%%
%%
handle_info(_Info, State) ->
    {ok, State}.


%%
%%
%%
terminate(_Arg, _State) ->
    ok.


%%
%%
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================


