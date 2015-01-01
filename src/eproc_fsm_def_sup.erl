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
%%  Default supervisor for FSM instances. It uses `simple_one_for_one`
%%  supervisor for managing the FSM processes. This is default implementation
%%  for the FSM supervisor, altrough registry implementations can have own.
%%
-module(eproc_fsm_def_sup).
-behaviour(supervisor).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1, start_fsm/2]).
-export([init/1]).
-include("eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Start this supervisor.
%%
-spec start_link(
        Name :: otp_name()
    ) ->
        pid() | {error, term()} | term().

start_link(Name) ->
    supervisor:start_link(Name, ?MODULE, {}).


%%
%%  Starts new `eproc_fsm` instance using the `eproc_fsm:start_link/2` function.
%%
-spec start_fsm(
        Supervisor      :: otp_ref(),
        StartLinkArgs   :: list()
    ) ->
        {ok, pid()}.

start_fsm(Supervisor, StartLinkArgs) when is_list(StartLinkArgs) ->
    {ok, _Pid} = supervisor:start_child(Supervisor, StartLinkArgs).



%% =============================================================================
%%  Callbacks for `supervisor`.
%% =============================================================================

%%
%%  Supervisor configuration.
%%
init({}) ->
    {ok, {{simple_one_for_one, 100, 10}, [
        {eproc_fsm, {eproc_fsm, start_link, []}, transient, 10000, worker, [eproc_fsm]}
    ]}}.


