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
%%% An attachment is a large chunk of data, that is manipulated by the FSM as
%%% a single value (unstructured, at least from the viewpoint of the FSM).
%%%
%%% In order to avoid duplication of such data in the store, it should
%%% not be stored in the FSM state or its messages. I.e. the attachment
%%% should not be passed as a value to the FSM. A typical solution for such
%%% problem is to store the value of the attachment and to pass around only
%%% a reference to it.
%%%
%%% This module provides an interface for storing fsm attachments. In this
%%% module, an attachment is refereced by a key, and can be associated with
%%% some FSM.
%%%
-module(eproc_attachment).
-compile([{parse_transform, lager_transform}]).
-export([save/5, read/2, delete/2, cleanup/2]).
-include("eproc.hrl").


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%  This function saves attachment using Key as key and Value as value.
%%  If Owner is provided, the attacment is associated with the fsm and therefore
%%  may be deleted some time after fsm terminates or explicitelly by calling cleanup/2.
%%  If Owner is undefined, attachment is stored until it is explicitelly deleted
%%  using delete/2. (NOTE: a possible source of memory leak).
%%
%%  A single option {overwrite, boolean()} is handled. Default is {overwrite, false}.
%%  When overwrite is false and the attachment with key Key is already registered,
%%  the function responds with {error, duplicate}. If however overwrite is true,
%%  then previous value and owner are reset with Value and Owner.
%%
-spec save(
        Store :: store_ref(),
        Key   :: term(),
        Value :: term(),
        Owner :: fsm_ref() | undefined,
        Opts  :: proplists:proplist()
    ) ->
        ok |
        {error, duplicate} |
        {error, Reason :: term()}.

save(Store, Key, Value, Owner, Opts) ->
    eproc_store:attachment_save(Store, Key, Value, Owner, Opts).


%%
%%  This function returns attachment value associated with given Key.
%%  If Key is not registered, {error, not_found} is returned.
%%
-spec read(
        Store :: store_ref(),
        Key   :: term()
    ) ->
        {ok, Value :: term()} |
        {error, not_found} |
        {error, Reason :: term()}.

read(Store, Key) ->
    eproc_store:attachment_read(Store, Key).


%%
%%  This function deletes attachment value associated with given Key.
%%
-spec delete(
        Store :: store_ref(),
        Key   :: term()
    ) ->
        ok.

delete(Store, Key) ->
    eproc_store:attachment_delete(Store, Key).


%%
%%  This function deletes all attachments associated with given fsm.
%%
-spec cleanup(
        Store :: store_ref(),
        Owner :: fsm_ref()
    ) ->
        ok | {error, Reason :: term()}.

cleanup(Store, Owner) ->
    eproc_store:attachment_cleanup(Store, Owner).


