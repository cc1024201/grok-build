#!/usr/bin/env python3
from pathlib import Path

path = Path("crates/codegen/xai-grok-agent/src/discovery.rs")
text = path.read_text()

old = '''/// User-level agent directories in priority order: user grok agents, `.claude`
/// compat agents, then bundled. `.grok` dirs resolve from `grok_home`
/// (GROK_HOME-aware) plus the legacy literal `~/.grok` when GROK_HOME points
/// elsewhere; `.claude` resolves from `home`.
pub(crate) fn user_agent_dirs(
    home: Option<&Path>,
    grok_home: Option<&Path>,
) -> Vec<(std::path::PathBuf, AgentScope)> {
    // Legacy literal ~/.grok, included only when it differs from grok_home
    // (i.e. GROK_HOME points elsewhere) so agents left in the old location are
    // still discovered and stay consistent with scope_from_path classification.
    let legacy_grok = home
        .map(|h| h.join(".grok"))
        .filter(|legacy| grok_home != Some(legacy.as_path()));

    let mut dirs = Vec::new();
    if let Some(g) = grok_home {
        dirs.push((g.join("agents"), AgentScope::User));
    }
    if let Some(l) = &legacy_grok {
        dirs.push((l.join("agents"), AgentScope::User));
    }
    if let Some(h) = home {
        dirs.push((h.join(".claude").join("agents"), AgentScope::User));
    }
    if let Some(g) = grok_home {
        dirs.push((g.join("bundled").join("agents"), AgentScope::Bundled));
    }
    if let Some(l) = &legacy_grok {
        dirs.push((l.join("bundled").join("agents"), AgentScope::Bundled));
    }
    dirs
}
'''

new = '''/// User-level agent directories in priority order: user grok agents, `.claude`
/// compat agents, then bundled. `.grok` dirs resolve from `grok_home`
/// (GROK_HOME-aware). Normal distributions also inspect the legacy literal
/// `~/.grok` when GROK_HOME points elsewhere; isolated distributions suppress
/// that compatibility fallback so they never import the official Grok agent
/// catalog by accident. `.claude` resolves from `home`.
pub(crate) fn user_agent_dirs(
    home: Option<&Path>,
    grok_home: Option<&Path>,
) -> Vec<(std::path::PathBuf, AgentScope)> {
    user_agent_dirs_with_legacy(
        home,
        grok_home,
        std::env::var_os("GROK_ULTRA_DISTRIBUTION").is_none(),
    )
}

fn user_agent_dirs_with_legacy(
    home: Option<&Path>,
    grok_home: Option<&Path>,
    include_legacy_grok: bool,
) -> Vec<(std::path::PathBuf, AgentScope)> {
    // Legacy literal ~/.grok, included only when it differs from grok_home
    // (i.e. GROK_HOME points elsewhere) so agents left in the old location are
    // still discovered and stay consistent with scope_from_path classification.
    let legacy_grok = if include_legacy_grok {
        home.map(|h| h.join(".grok"))
            .filter(|legacy| grok_home != Some(legacy.as_path()))
    } else {
        None
    };

    let mut dirs = Vec::new();
    if let Some(g) = grok_home {
        dirs.push((g.join("agents"), AgentScope::User));
    }
    if let Some(l) = &legacy_grok {
        dirs.push((l.join("agents"), AgentScope::User));
    }
    if let Some(h) = home {
        dirs.push((h.join(".claude").join("agents"), AgentScope::User));
    }
    if let Some(g) = grok_home {
        dirs.push((g.join("bundled").join("agents"), AgentScope::Bundled));
    }
    if let Some(l) = &legacy_grok {
        dirs.push((l.join("bundled").join("agents"), AgentScope::Bundled));
    }
    dirs
}
'''

if old not in text:
    raise SystemExit("user_agent_dirs block did not match current source")
text = text.replace(old, new, 1)

anchor = '''    #[test]
    fn user_agent_dirs_dedups_legacy_when_grok_home_is_dot_grok() {
'''
test = '''    #[test]
    fn user_agent_dirs_excludes_official_grok_home_for_isolated_distribution() {
        let home = Path::new("/home/u");
        let grok = Path::new("/home/u/.grok-ultra");
        let paths: Vec<_> = user_agent_dirs_with_legacy(Some(home), Some(grok), false)
            .into_iter()
            .map(|(p, _)| p)
            .collect();
        assert!(paths.contains(&grok.join("agents")));
        assert!(paths.contains(&grok.join("bundled").join("agents")));
        assert!(!paths.contains(&home.join(".grok").join("agents")));
        assert!(!paths.contains(&home.join(".grok").join("bundled").join("agents")));
        assert!(paths.contains(&home.join(".claude").join("agents")));
    }

'''
if anchor not in text:
    raise SystemExit("test insertion anchor did not match current source")
text = text.replace(anchor, test + anchor, 1)
path.write_text(text)
