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
%%  Behaviour for EProc Store archive.
%%  This behaviour is not required, altrough recommended to be used
%%  by store implementations and archive implementations. This will
%%  allow to combine them as needed.
%%
-module(eproc_archive).
-compile([{parse_transform, lager_transform}]).
-export([ref/2, archive_instance/4, archive_transitions/4]).
-export_type([ref/0]).
-include("eproc.hrl").

-opaque ref() :: {Callback :: module(), Args :: term()}.


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  Archive entire FSM instance.
%%
-callback archive_instance(
        ArchArgs    :: term(),
        Instance    :: #instance{},
        Transitions :: [#transition{}],
        Messages    :: [#message{}]
    ) -> ok.


%%
%%  Archive part of FSM instance transitions.
%%
-callback archive_transitions(
        ArchArgs    :: term(),
        Instance    :: #instance{},
        Transitions :: [#transition{}],
        Messages    :: [#message{}]
    ) -> ok.



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Create an archive reference.
%%
-spec ref(module(), term()) -> {ok, archive_ref()}.

ref(Module, Args) ->
    {ok, {Module, Args}}.


%%
%%  Archive entire FSM instance.
%%
-spec archive_instance(
        ArchiveRef  :: archive_ref(),
        Instance    :: #instance{},
        Transitions :: [#transition{}],
        Messages    :: [#message{}]
    ) -> ok.

archive_instance(ArchiveRef, Instance, Transitions, Messages) ->
    {ArchMod, ArchArgs} = ArchiveRef,
    ArchMod:archive_instance(ArchArgs, Instance, Transitions, Messages).


%%
%%  Archive part of FSM instance transitions.
%%
-spec archive_transitions(
        ArchiveRef  :: archive_ref(),
        Instance    :: #instance{},
        Transitions :: [#transition{}],
        Messages    :: [#message{}]
    ) -> ok.

archive_transitions(ArchiveRef, Instance, Transitions, Messages) ->
    {ArchMod, ArchArgs} = ArchiveRef,
    ArchMod:archive_transitions(ArchArgs, Instance, Transitions, Messages).


