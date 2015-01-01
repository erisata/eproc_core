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
%%  Encodes / decodes erlang terms to/from XML using xmerl.
%%
-module(eproc_codec_xml).
-behaviour(eproc_codec).
-export([encode/2, decode/2]).
-include_lib("xmerl/include/xmerl.hrl").


%% =============================================================================
%%  Callbacks for `eproc_codec`.
%% =============================================================================

%%
%%  Encode term to XML.
%%
encode(_CodecArgs, Term) ->
    Xml = xmerl:export_simple([encode(Term)], xmerl_xml),
    {ok, Xml}.


%%
%%  Decode XML to Erlang term.
%%
decode(CodecArgs, Xml) when is_binary(Xml) ->
    decode(CodecArgs, erlang:binary_to_list(Xml));

decode(_CodecArgs, Xml) when is_list(Xml) ->
    {RootElement, []} = xmerl_scan:string(Xml),
    Term = decode_xmerl(RootElement),
    {ok, Term}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Encode to xmerl tuples.
%%
encode(Term) when is_tuple(Term) ->
    L = tuple_to_list(Term),
    {tuple, [encode(E) || E <- L]};

encode(Term = [H | _]) when is_integer(H), H < 256 ->
    {string, [Term]};

encode(Term) when is_list(Term) ->
    {list, [encode(E) || E <- Term]};

encode(Term) when is_atom(Term) ->
    A = atom_to_list(Term),
    {atom, [A]};

encode(Term) when is_integer(Term) ->
    I = integer_to_list(Term),
    {integer, [I]};

encode(Term) when is_binary(Term) ->
    B = binary_to_list(Term),
    {binary, [B]}.


%%
%%  Decode to xmerl tuples.
%%
decode_xmerl(#xmlElement{name = integer, content = Content}) ->
    erlang:list_to_integer(get_xmerl_elem_text(Content));

decode_xmerl(#xmlElement{name = tuple, content = Content}) ->
    Decoded = [decode_xmerl(C) || C <- Content],
    erlang:list_to_tuple(Decoded);

decode_xmerl(#xmlElement{name = binary, content = Content}) ->
    [#xmlText{value = Value}] = Content,
    erlang:list_to_binary(Value);

decode_xmerl(#xmlElement{name = list, content = Content}) ->
    [decode_xmerl(C) || C <- Content];

decode_xmerl(#xmlElement{name = string, content = Content}) ->
    [#xmlText{value = Value}] = Content,
    Value;

decode_xmerl(#xmlElement{name = atom, content = Content}) ->
    erlang:list_to_atom(get_xmerl_elem_text(Content)).


%%
%%  Extract text from an element.
%%
get_xmerl_elem_text([]) ->
    "";

get_xmerl_elem_text([#xmlText{value = Value} | T]) ->
    Value ++ get_xmerl_elem_text(T);

get_xmerl_elem_text([#xmlComment{} | T]) ->
    get_xmerl_elem_text(T).


