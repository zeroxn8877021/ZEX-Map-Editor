# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : map_object.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name MapObject
extends RefCounted
## One placed object. The data model only stores the asset id + transform; views build MultiMeshes from it.
var asset: String = ""
var xf: Transform3D = Transform3D.IDENTITY
var tag: int = 0    # free use (e.g. scatter group id)

static func make(a: String, t: Transform3D) -> MapObject:
	var o := MapObject.new()
	o.asset = a
	o.xf = t
	return o
