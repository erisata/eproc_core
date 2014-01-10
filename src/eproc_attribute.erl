%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, Ltd.
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
%%  TODO: Description.
%%
%%  API for the eproc_fsm.
%%  API for an attribute manager (for attaching attrs to FSM).
%%  SPI for the attribute manager (for handling attached attrs).
%%
%%  Differentiate between:
%%    * Attributes.
%%    * Attribute actions.
%%
%%  TODO: Define this while implementing `eproc_timer` module!!!
%%
-module(eproc_attribute).
-export([action/4, action/3]).
-export([started/1, created/0, updated/0, removed/0]).
-include("eproc.hrl").



%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  FSM started.
%%
-callback started(
        ActiveAttrs :: [#attribute{}]
    ) ->
        ok |
        {error, Reason :: term()}.

%%
%%  Attribute created.
%%
-callback created(
        Name    :: term(),
        Action  :: #attr_action{},
        Scope   :: term()
    ) ->
        {ok, Data :: term()} |
        {error, Reason :: term()}.

%%
%%  Attribute updated by user.
%%
-callback updated(
        Attribute   :: #attribute{},
        Action      :: #attr_action{}
    ) ->
        {ok, Data :: term()} |
        {error, Reason :: term()}.

%%
%%  Attribute removed by `eproc_fsm`.
%%
-callback removed(
        Attribute :: #attribute{}
    ) ->
        {ok, Data :: term()} |
        {error, Reason :: term()}.

%%
%%  Store attribute information in the store.
%%  This callback is invoked in the context of `eproc_store`.
%%  TODO: Remove this, make this module a behaviour, that should
%%  be implemented by the store.
%%
-callback store(
        Store       :: store_ref(),
        Attribute   :: #attribute{},
        Args        :: term()
    ) ->
        ok |
        {error, Reason :: term()}.



%% =============================================================================
%%  Public API.
%% =============================================================================


%%
%%
%%
action(Module, Name, Action, Scope) ->
    eproc_fsm:register_attr_action(Module, Name, Action, Scope).


%%
%%
%%
action(Module, Name, Action) ->
    action(Module, Name, Action, undefined).



%%
%%  Invoked, when the corresponding FSM is started (become online).
%%
started(ActiveAttrs) ->
    ok. % TODO


%%
%%  Invoked, when an attribute is added or updated in the FSM.
%%
created() ->
    ok. % TODO


%%
%%
%%
updated() ->
    ok. % TODO


%%
%%  Invoked, when an attribute is removed. There can be several reasons for this:
%%    * User asked to remove the attribute.
%%    * The FSM exited the scope, specified for the attribute.
%%
removed() ->
    ok. % TODO


%% =============================================================================
%%  Internal functions.
%% =============================================================================
