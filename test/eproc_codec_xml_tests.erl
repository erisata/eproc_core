%/--------------------------------------------------------------------
%| Copyright 2013 Robus, Ltd.
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
-module(eproc_codec_xml_tests).
-compile([{parse_transform, lager_transform}]).
-include_lib("eunit/include/eunit.hrl").


%%
%%  Test primitive encoding rules.
%%
encode_test() ->
    {ok, <<"<integer>1</integer>">>} = eproc_codec_xml:encode(1),
    {ok, <<"<atom>asd</atom>">>}     = eproc_codec_xml:encode(asd),
    {ok, <<"<string>asd</string>">>} = eproc_codec_xml:encode("asd"),
    {ok, <<"<tuple></tuple>">>}      = eproc_codec_xml:encode({}),
    {ok, <<"<list></list>">>}        = eproc_codec_xml:encode([]),
    {ok, <<"<binary>asd</binary>">>} = eproc_codec_xml:encode(<<"asd">>),
    ok.


%%
%%  Test primitive decoding rules.
%%
decode_test() ->
    {ok, 1}         = eproc_codec_xml:decode(<<"<integer>1</integer>">>),
    {ok, asd}       = eproc_codec_xml:decode(<<"<atom>asd</atom>">>),
    {ok, "asd"}     = eproc_codec_xml:decode(<<"<string>asd</string>">>),
    {ok, {}}        = eproc_codec_xml:decode(<<"<tuple></tuple>">>),
    {ok, []}        = eproc_codec_xml:decode(<<"<list></list>">>),
    {ok, <<"asd">>} = eproc_codec_xml:decode(<<"<binary>asd</binary>">>),
    ok.


%%
%%  Test encoding/decoding cycle.
%%
codec_test() ->
    Decoded = {[1, 2, "123"], [{{{ok, 1, "qwe"}, [asd]}}]},
    {ok, Encoded} = eproc_codec_xml:encode(Decoded),
    {ok, Decoded} = eproc_codec_xml:decode(Encoded),
    ok.


