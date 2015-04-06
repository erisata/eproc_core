

# Module eproc_meta #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`eproc_fsm_attr`](eproc_fsm_attr.md).

__This module defines the `eproc_meta` behaviour.__
<br></br>
 Required callback functions: `metadata/1`.
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_tag-2">add_tag/2</a></td><td></td></tr><tr><td valign="top"><a href="#get_instances-2">get_instances/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_created-4">handle_created/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_event-4">handle_event/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_removed-3">handle_removed/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_updated-5">handle_updated/5</a></td><td></td></tr><tr><td valign="top"><a href="#init-2">init/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="add_tag-2"></a>

### add_tag/2 ###


<pre><code>
add_tag(Tag::binary() | integer() | atom() | list(), Type::binary() | integer() | atom() | list()) -&gt; ok
</code></pre>

<br></br>



<a name="get_instances-2"></a>

### get_instances/2 ###


<pre><code>
get_instances(Query::{tags, [{Tag::binary(), Type::binary() | undefined}]}, Opts::[{store, <a href="#type-store_ref">store_ref()</a>}]) -&gt; {ok, [<a href="#type-inst_id">inst_id()</a>]}
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


