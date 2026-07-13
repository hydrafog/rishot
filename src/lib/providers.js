
function parseHyprland(monitorsJson, clientsJson) {
  var rects = [];
  try {
    var activeWs = [];
    var monitors = JSON.parse(monitorsJson);
    for (var m = 0; m < monitors.length; m++) {
      if (monitors[m].activeWorkspace)
        activeWs.push(monitors[m].activeWorkspace.id);
    }
    var clients = JSON.parse(clientsJson);
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i];
      if (!c.mapped || c.hidden) continue;
      if (!c.workspace || activeWs.indexOf(c.workspace.id) === -1) continue;
      if (!c.size || c.size[0] <= 0 || c.size[1] <= 0) continue;
      if (!c.at) continue;
      rects.push({
        x: c.at[0],
        y: c.at[1],
        w: c.size[0],
        h: c.size[1],
        z: c.focusHistoryID,
      });
    }
  } catch (e) {
    return [];
  }
  return rects;
}

function isSwayWindow(node) {
  var hasChildren =
    (node.nodes && node.nodes.length > 0) ||
    (node.floating_nodes && node.floating_nodes.length > 0);
  if (hasChildren) return false;
  if (!node.rect || node.rect.width <= 0 || node.rect.height <= 0) return false;
  if (node.visible === false) return false;
  var isApp =
    (typeof node.app_id === "string" && node.app_id.length > 0) ||
    (node.window !== undefined && node.window !== null) ||
    (node.pid !== undefined && node.pid !== null);
  return isApp;
}

function parseSway(treeJson) {
  var found = [];
  try {
    var tree = JSON.parse(treeJson);
    var walk = function (node) {
      if (!node) return;
      var children = (node.nodes || []).concat(node.floating_nodes || []);
      for (var i = 0; i < children.length; i++) walk(children[i]);
      if (isSwayWindow(node)) {
        found.push({
          x: node.rect.x,
          y: node.rect.y,
          w: node.rect.width,
          h: node.rect.height,
        });
      }
    };
    walk(tree);
  } catch (e) {
    return [];
  }
  var n = found.length;
  var rects = [];
  for (var k = 0; k < n; k++) {
    rects.push({
      x: found[k].x,
      y: found[k].y,
      w: found[k].w,
      h: found[k].h,
      z: n - 1 - k,
    });
  }
  return rects;
}

function niriWorkspaceMap(workspaces) {
  var map = {};
  if (Array.isArray(workspaces)) {
    for (var i = 0; i < workspaces.length; i++) {
      var ws = workspaces[i];
      if (ws && ws.id !== undefined && ws.id !== null && ws.output)
        map[ws.id] = ws.output;
    }
  }
  return map;
}

function niriOutputMap(outputs) {
  var map = {};
  if (Array.isArray(outputs)) {
    for (var i = 0; i < outputs.length; i++) {
      var o = outputs[i];
      if (o && o.name && o.logical) map[o.name] = o.logical;
    }
  } else if (outputs && typeof outputs === "object") {
    for (var name in outputs) {
      if (!Object.prototype.hasOwnProperty.call(outputs, name)) continue;
      var entry = outputs[name];
      if (entry && entry.logical) map[name] = entry.logical;
    }
  }
  return map;
}

function parseNiri(windowsJson, workspacesJson, outputsJson) {
  var rects = [];
  try {
    var windows = JSON.parse(windowsJson);
    var workspaceMap = niriWorkspaceMap(JSON.parse(workspacesJson));
    var outputMap = niriOutputMap(JSON.parse(outputsJson));
    var counter = 1;
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i];
      var layout = win.layout;
      if (!layout) continue;
      var tilePos = layout.tile_pos_in_workspace_view;
      if (!tilePos) continue;
      var off = layout.window_offset_in_tile || [0, 0];
      var size = layout.window_size;
      if (!size || size[0] <= 0 || size[1] <= 0) continue;
      var outName = workspaceMap[win.workspace_id];
      if (!outName) continue;
      var out = outputMap[outName];
      if (!out) continue;
      rects.push({
        x: out.x + tilePos[0] + off[0],
        y: out.y + tilePos[1] + off[1],
        w: size[0],
        h: size[1],
        z: win.is_focused ? 0 : counter++,
      });
    }
  } catch (e) {
    return [];
  }
  return rects;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { parseHyprland, parseSway, parseNiri };
}


