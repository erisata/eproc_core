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
%%  Void EProc archive. Just prints all data to log and discards it.
%%  This implementation can be used if no archiving is needed.
%%
-module(eproc_archive_void).
-behaviour(eproc_archive).
-compile([{parse_transform, lager_transform}]).
-export([ref/0]).
-export([archive_instance/4, archive_transitions/4]).
-include("eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Returns a reference to this archive.
%%
-spec ref() -> {ok, archive_ref()}.

ref() ->
    eproc_archive:ref(?MODULE, {}).



%% =============================================================================
%%  Callbacks for `eproc_codec`.
%% =============================================================================

%%
%%  Archive entire FSM instance.
%%
archive_instance(_ArchArgs, Instance, Transitions, Messages) ->
    lager:debug(
        "Discarding instance: ~p, transitions=~p, messages=~p",
        [Instance, Transitions, Messages]
    ),
    ok.


%%
%%  Archive part of FSM instance transitions.
%%
archive_transitions(_ArchArgs, Instance, Transitions, Messages) ->
    lager:debug(
        "Discarding instance transitions: instance=~p, transitions=~p, messages=~p",
        [Instance, Transitions, Messages]
    ),
    ok.


