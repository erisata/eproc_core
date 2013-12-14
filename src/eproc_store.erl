%/--------------------------------------------------------------------
%| Copyright 2013 Karolis Petrauskas
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
%%  TODO: Desc.
%%
-module(eproc_store).
-compile([{parse_transform, lager_transform}]).
-export([ref/2, add_instance/4]).
-export_type([ref/0]).
-include("eproc.hrl").

-opaque ref() :: {Callback :: module(), Args :: term()}.


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

-callback add_instance(
        StoreArgs   :: term(),
        FsmModule   :: module(),
        FsmArgs     :: term(),
        FsmGroup    :: inst_group()
    ) ->
        {ok, inst_id()}.


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Create store reference.
%%
-spec ref(
        module(),
        term()
        ) ->
        {ok, store_ref()}.

ref(Module, Args) ->
    {ok, {Module, Args}}.


%%
%%
%%
add_instance({StoreMod, StoreArgs}, FsmModule, FsmArgs, FsmGroup) ->
    StoreMod:add_instance(StoreArgs, FsmModule, FsmArgs, FsmGroup).

