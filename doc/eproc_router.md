

# Module eproc_router #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`eproc_fsm_attr`](eproc_fsm_attr.md).
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_key-2">add_key/2</a></td><td></td></tr><tr><td valign="top"><a href="#add_key-3">add_key/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_created-4">handle_created/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_event-4">handle_event/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_removed-3">handle_removed/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_updated-5">handle_updated/5</a></td><td></td></tr><tr><td valign="top"><a href="#init-2">init/2</a></td><td></td></tr><tr><td valign="top"><a href="#lookup-1">lookup/1</a></td><td></td></tr><tr><td valign="top"><a href="#lookup-2">lookup/2</a></td><td></td></tr><tr><td valign="top"><a href="#lookup_send-2">lookup_send/2</a></td><td></td></tr><tr><td valign="top"><a href="#lookup_send-3">lookup_send/3</a></td><td></td></tr><tr><td valign="top"><a href="#lookup_sync_send-2">lookup_sync_send/2</a></td><td></td></tr><tr><td valign="top"><a href="#lookup_sync_send-3">lookup_sync_send/3</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="add_key-2"></a>

### add_key/2 ###


<pre><code>
add_key(Key::term(), Scope::<a href="#type-scope">scope()</a> | next | undefined) -&gt; ok
</code></pre>

<br></br>



<a name="add_key-3"></a>

### add_key/3 ###


<pre><code>
add_key(Key::term(), Scope::<a href="#type-scope">scope()</a> | next | undefined, Opts::[sync | uniq]) -&gt; ok | {error, exist} | {error, Reason::term()}
</code></pre>

<br></br>



<a name="handle_created-4"></a>

### handle_created/4 ###

`handle_created(InstId, Attribute, X3, Scope) -> any()`


<a name="handle_event-4"></a>

### handle_event/4 ###

`handle_event(InstId, Attribute, AttrState, Event) -> any()`


<a name="handle_removed-3"></a>

### handle_removed/3 ###

`handle_removed(InstId, Attribute, AttrState) -> any()`


<a name="handle_updated-5"></a>

### handle_updated/5 ###

`handle_updated(InstId, Attribute, AttrState, X4, Scope) -> any()`


<a name="init-2"></a>

### init/2 ###

`init(InstId, ActiveAttrs) -> any()`


<a name="lookup-1"></a>

### lookup/1 ###


<pre><code>
lookup(Key::term()) -&gt; {ok, [<a href="#type-inst_id">inst_id()</a>]} | {error, Reason::term()}
</code></pre>

<br></br>



<a name="lookup-2"></a>

### lookup/2 ###


<pre><code>
lookup(Key::term(), Opts::[{store, <a href="#type-store_ref">store_ref()</a>}]) -&gt; {ok, [<a href="#type-inst_id">inst_id()</a>]} | {error, Reason::term()}
</code></pre>

<br></br>



<a name="lookup_send-2"></a>

### lookup_send/2 ###


<pre><code>
lookup_send(Key::term(), Fun::fun((<a href="#type-fsm_ref">fsm_ref()</a>) -&gt; any())) -&gt; ok | {error, (not_found | multiple | term())}
</code></pre>

<br></br>



<a name="lookup_send-3"></a>

### lookup_send/3 ###


<pre><code>
lookup_send(Key::term(), Opts::[(uniq | {store, <a href="#type-store_ref">store_ref()</a>})], Fun::fun((<a href="#type-fsm_ref">fsm_ref()</a>) -&gt; any())) -&gt; ok | {error, (not_found | multiple | term())}
</code></pre>

<br></br>



<a name="lookup_sync_send-2"></a>

### lookup_sync_send/2 ###


<pre><code>
lookup_sync_send(Key::term(), Fun::fun((<a href="#type-fsm_ref">fsm_ref()</a>) -&gt; Reply::term())) -&gt; Reply::term() | {error, (not_found | multiple | term())}
</code></pre>

<br></br>



<a name="lookup_sync_send-3"></a>

### lookup_sync_send/3 ###


<pre><code>
lookup_sync_send(Key::term(), Opts::[{store, <a href="#type-store_ref">store_ref()</a>}], Fun::fun((<a href="#type-fsm_ref">fsm_ref()</a>) -&gt; Reply::term())) -&gt; Reply::term() | {error, (not_found | multiple | term())}
</code></pre>

<br></br>



