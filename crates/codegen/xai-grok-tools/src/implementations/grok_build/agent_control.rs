//! Model-facing controls for Grok Build's persistent subagent registry.
//!
//! These tools are exposed only by the `grok-build-ultra` profile. They reuse
//! the existing coordinator, cancellation, interjection, resume, and TaskTool
//! paths instead of introducing a second multi-agent runtime.

use crate::implementations::grok_build::task::TaskTool;
use crate::implementations::grok_build::task::backend::SubagentBackendResource;
use crate::implementations::grok_build::task::types::{
    SubagentAgentSummary, SubagentCancelOutcome, SubagentMessageOutcome,
};
use crate::types::requirements::{Expr, ToolRequirement};
use crate::types::tool::{ToolKind, ToolNamespace};
use xai_tool_types::TaskToolInput;

fn task_requirement() -> Expr<ToolRequirement> {
    Expr::Value(ToolRequirement::tool_kind(ToolKind::Task))
}

async fn backend_from_context(
    ctx: &xai_tool_runtime::ToolCallContext,
) -> Result<SubagentBackendResource, xai_tool_runtime::ToolError> {
    use crate::types::tool_metadata::shared_resources;
    let resources = shared_resources(ctx)?;
    let guard = resources.lock().await;
    guard
        .get::<SubagentBackendResource>()
        .cloned()
        .ok_or_else(|| {
            xai_tool_runtime::ToolError::custom(
                "missing_resource",
                "SubagentBackendResource (subagent support not initialized)",
            )
        })
}

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize, schemars::JsonSchema)]
pub struct ListAgentsInput {}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, schemars::JsonSchema)]
pub struct ListAgentsOutput {
    pub agents: Vec<SubagentAgentSummary>,
}

impl xai_tool_runtime::ToolOutput for ListAgentsOutput {}

#[derive(Debug, Default)]
pub struct ListAgentsTool;

impl crate::types::tool_metadata::ToolMetadata for ListAgentsTool {
    fn kind(&self) -> ToolKind {
        ToolKind::Other
    }

    fn tool_namespace(&self) -> ToolNamespace {
        ToolNamespace::GrokBuild
    }

    fn description_template(&self) -> &str {
        "List subagents owned by this session, including initializing, running, completed, failed, and cancelled agents. Use this before messaging, following up, interrupting, or waiting when you need the current roster."
    }

    fn requires_expr(&self) -> Expr<ToolRequirement> {
        task_requirement()
    }

    fn is_read_only(&self) -> bool {
        true
    }
}

impl xai_tool_runtime::Tool for ListAgentsTool {
    type Args = ListAgentsInput;
    type Output = ListAgentsOutput;

    fn id(&self) -> xai_tool_protocol::ToolId {
        xai_tool_protocol::ToolId::new("list_subagents").expect("valid tool id")
    }

    fn description(
        &self,
        _ctx: &xai_tool_runtime::ListToolsContext,
    ) -> xai_tool_types::ToolDescription {
        xai_tool_types::ToolDescription::new(
            "list_subagents",
            crate::types::tool_metadata::ToolMetadata::sanitized_description_template(self),
        )
    }

    fn capabilities(&self) -> xai_tool_protocol::ToolCapabilities {
        xai_tool_protocol::ToolCapabilities {
            is_read_only: true,
            tool_scope: Some(xai_tool_protocol::ToolScope::Read),
            ..Default::default()
        }
    }

    async fn run(
        &self,
        ctx: xai_tool_runtime::ToolCallContext,
        _input: ListAgentsInput,
    ) -> Result<ListAgentsOutput, xai_tool_runtime::ToolError> {
        let backend = backend_from_context(&ctx).await?;
        Ok(ListAgentsOutput {
            agents: backend.backend().list_agents().await,
        })
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, schemars::JsonSchema)]
pub struct SendMessageInput {
    #[schemars(description = "Subagent id returned by spawn_subagent or list_agents.")]
    pub target: String,
    #[schemars(description = "Non-empty message to deliver to the running subagent.")]
    pub message: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, schemars::JsonSchema)]
pub struct SendMessageOutput {
    pub target: String,
    pub status: String,
}

impl xai_tool_runtime::ToolOutput for SendMessageOutput {}

#[derive(Debug, Default)]
pub struct SendMessageTool;

impl crate::types::tool_metadata::ToolMetadata for SendMessageTool {
    fn kind(&self) -> ToolKind {
        ToolKind::Other
    }

    fn tool_namespace(&self) -> ToolNamespace {
        ToolNamespace::GrokBuild
    }

    fn description_template(&self) -> &str {
        "Send a message to a currently-running subagent. The message is injected at the next safe point without cancelling the child. For an already-completed child, use followup_task so its conversation is resumed."
    }

    fn requires_expr(&self) -> Expr<ToolRequirement> {
        task_requirement()
    }

    fn is_read_only(&self) -> bool {
        false
    }
}

impl xai_tool_runtime::Tool for SendMessageTool {
    type Args = SendMessageInput;
    type Output = SendMessageOutput;

    fn id(&self) -> xai_tool_protocol::ToolId {
        xai_tool_protocol::ToolId::new("send_subagent_message").expect("valid tool id")
    }

    fn description(
        &self,
        _ctx: &xai_tool_runtime::ListToolsContext,
    ) -> xai_tool_types::ToolDescription {
        xai_tool_types::ToolDescription::new(
            "send_subagent_message",
            crate::types::tool_metadata::ToolMetadata::sanitized_description_template(self),
        )
    }

    fn capabilities(&self) -> xai_tool_protocol::ToolCapabilities {
        xai_tool_protocol::ToolCapabilities {
            is_read_only: false,
            tool_scope: Some(xai_tool_protocol::ToolScope::Write),
            ..Default::default()
        }
    }

    async fn run(
        &self,
        ctx: xai_tool_runtime::ToolCallContext,
        input: SendMessageInput,
    ) -> Result<SendMessageOutput, xai_tool_runtime::ToolError> {
        let message = input.message.trim();
        if input.target.trim().is_empty() || message.is_empty() {
            return Err(xai_tool_runtime::ToolError::invalid_arguments(
                "target and message must both be non-empty",
            ));
        }
        let backend = backend_from_context(&ctx).await?;
        match backend
            .backend()
            .send_message(input.target.trim(), message.to_string())
            .await
        {
            SubagentMessageOutcome::Delivered => Ok(SendMessageOutput {
                target: input.target,
                status: "queued".to_string(),
            }),
            SubagentMessageOutcome::Initializing => {
                Err(xai_tool_runtime::ToolError::invalid_arguments(
                    "The target subagent is still initializing. Retry shortly or continue other parent work.",
                ))
            }
            SubagentMessageOutcome::Completed => {
                Err(xai_tool_runtime::ToolError::invalid_arguments(
                    "The target subagent has completed. Use followup_task to resume its conversation.",
                ))
            }
            SubagentMessageOutcome::NotFound => {
                Err(xai_tool_runtime::ToolError::invalid_arguments(
                    "The target subagent was not found in this session.",
                ))
            }
            SubagentMessageOutcome::Unavailable => Err(xai_tool_runtime::ToolError::custom(
                "message_unavailable",
                "The target subagent cannot currently receive messages.",
            )),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, schemars::JsonSchema)]
pub struct FollowupTaskInput {
    #[schemars(description = "Subagent id returned by spawn_subagent or list_agents.")]
    pub target: String,
    #[schemars(description = "Non-empty follow-up task or corrective instruction.")]
    pub message: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, schemars::JsonSchema)]
pub struct FollowupTaskOutput {
    pub task_name: String,
    pub target: String,
    pub mode: String,
}

impl xai_tool_runtime::ToolOutput for FollowupTaskOutput {}

#[derive(Debug, Default)]
pub struct FollowupTaskTool;

impl crate::types::tool_metadata::ToolMetadata for FollowupTaskTool {
    fn kind(&self) -> ToolKind {
        ToolKind::Other
    }

    fn tool_namespace(&self) -> ToolNamespace {
        ToolNamespace::GrokBuild
    }

    fn description_template(&self) -> &str {
        "Give an existing subagent more work. Running agents receive the message in their current turn. Completed, failed, or cancelled agents are resumed from their persisted conversation as a new background child and the returned task_name becomes the new continuation handle."
    }

    fn requires_expr(&self) -> Expr<ToolRequirement> {
        task_requirement()
    }

    fn is_read_only(&self) -> bool {
        false
    }
}

impl xai_tool_runtime::Tool for FollowupTaskTool {
    type Args = FollowupTaskInput;
    type Output = FollowupTaskOutput;

    fn id(&self) -> xai_tool_protocol::ToolId {
        xai_tool_protocol::ToolId::new("followup_subagent").expect("valid tool id")
    }

    fn description(
        &self,
        _ctx: &xai_tool_runtime::ListToolsContext,
    ) -> xai_tool_types::ToolDescription {
        xai_tool_types::ToolDescription::new(
            "followup_subagent",
            crate::types::tool_metadata::ToolMetadata::sanitized_description_template(self),
        )
    }

    fn capabilities(&self) -> xai_tool_protocol::ToolCapabilities {
        xai_tool_protocol::ToolCapabilities {
            is_read_only: false,
            tool_scope: Some(xai_tool_protocol::ToolScope::Write),
            ..Default::default()
        }
    }

    async fn run(
        &self,
        ctx: xai_tool_runtime::ToolCallContext,
        input: FollowupTaskInput,
    ) -> Result<FollowupTaskOutput, xai_tool_runtime::ToolError> {
        let target = input.target.trim().to_string();
        let message = input.message.trim().to_string();
        if target.is_empty() || message.is_empty() {
            return Err(xai_tool_runtime::ToolError::invalid_arguments(
                "target and message must both be non-empty",
            ));
        }

        let backend = backend_from_context(&ctx).await?;
        let summary = backend
            .backend()
            .list_agents()
            .await
            .into_iter()
            .find(|agent| agent.subagent_id == target)
            .ok_or_else(|| {
                xai_tool_runtime::ToolError::invalid_arguments(
                    "The target subagent was not found in this session.",
                )
            })?;

        match summary.status.as_str() {
            "running" => match backend.backend().send_message(&target, message).await {
                SubagentMessageOutcome::Delivered => Ok(FollowupTaskOutput {
                    task_name: target.clone(),
                    target,
                    mode: "message".to_string(),
                }),
                _ => Err(xai_tool_runtime::ToolError::custom(
                    "followup_unavailable",
                    "The running subagent could not accept the follow-up message.",
                )),
            },
            "initializing" => Err(xai_tool_runtime::ToolError::invalid_arguments(
                "The target subagent is still initializing. Retry shortly.",
            )),
            "completed" | "failed" | "cancelled" => {
                let next_id = uuid::Uuid::now_v7().to_string();
                let description = format!("Follow up {}", &target[..target.len().min(8)]);
                let task_input = TaskToolInput {
                    prompt: message,
                    description,
                    subagent_type: summary.subagent_type,
                    run_in_background: true,
                    capability_mode: None,
                    isolation: None,
                    resume_from: Some(target.clone()),
                    cwd: None,
                    model: None,
                    task_id: Some(next_id.clone()),
                };
                let _ = xai_tool_runtime::Tool::run(&TaskTool, ctx, task_input).await?;
                Ok(FollowupTaskOutput {
                    task_name: next_id,
                    target,
                    mode: "resumed".to_string(),
                })
            }
            other => Err(xai_tool_runtime::ToolError::custom(
                "followup_unknown_status",
                format!("The target subagent has unsupported status '{other}'."),
            )),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, schemars::JsonSchema)]
pub struct InterruptAgentInput {
    #[schemars(description = "Subagent id returned by spawn_subagent or list_agents.")]
    pub target: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, schemars::JsonSchema)]
pub struct InterruptAgentOutput {
    pub target: String,
    pub previous_status: String,
    pub result: String,
}

impl xai_tool_runtime::ToolOutput for InterruptAgentOutput {}

#[derive(Debug, Default)]
pub struct InterruptAgentTool;

impl crate::types::tool_metadata::ToolMetadata for InterruptAgentTool {
    fn kind(&self) -> ToolKind {
        ToolKind::Other
    }

    fn tool_namespace(&self) -> ToolNamespace {
        ToolNamespace::GrokBuild
    }

    fn description_template(&self) -> &str {
        "Interrupt a subagent's current work. Its persisted conversation remains available to followup_task, which can resume it with a corrected direction."
    }

    fn requires_expr(&self) -> Expr<ToolRequirement> {
        task_requirement()
    }

    fn is_read_only(&self) -> bool {
        false
    }
}

impl xai_tool_runtime::Tool for InterruptAgentTool {
    type Args = InterruptAgentInput;
    type Output = InterruptAgentOutput;

    fn id(&self) -> xai_tool_protocol::ToolId {
        xai_tool_protocol::ToolId::new("interrupt_subagent").expect("valid tool id")
    }

    fn description(
        &self,
        _ctx: &xai_tool_runtime::ListToolsContext,
    ) -> xai_tool_types::ToolDescription {
        xai_tool_types::ToolDescription::new(
            "interrupt_subagent",
            crate::types::tool_metadata::ToolMetadata::sanitized_description_template(self),
        )
    }

    fn capabilities(&self) -> xai_tool_protocol::ToolCapabilities {
        xai_tool_protocol::ToolCapabilities {
            is_read_only: false,
            tool_scope: Some(xai_tool_protocol::ToolScope::Write),
            ..Default::default()
        }
    }

    async fn run(
        &self,
        ctx: xai_tool_runtime::ToolCallContext,
        input: InterruptAgentInput,
    ) -> Result<InterruptAgentOutput, xai_tool_runtime::ToolError> {
        let target = input.target.trim().to_string();
        if target.is_empty() {
            return Err(xai_tool_runtime::ToolError::invalid_arguments(
                "target must be non-empty",
            ));
        }
        let backend = backend_from_context(&ctx).await?;
        let previous_status = backend
            .backend()
            .list_agents()
            .await
            .into_iter()
            .find(|agent| agent.subagent_id == target)
            .map(|agent| agent.status)
            .unwrap_or_else(|| "not_found".to_string());
        let result = match backend.backend().cancel(&target).await {
            SubagentCancelOutcome::Cancelled => "interrupted".to_string(),
            SubagentCancelOutcome::AlreadyFinished { status } => {
                format!("already_finished:{status}")
            }
            SubagentCancelOutcome::NotFound => {
                return Err(xai_tool_runtime::ToolError::invalid_arguments(
                    "The target subagent was not found in this session.",
                ));
            }
        };
        Ok(InterruptAgentOutput {
            target,
            previous_status,
            result,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::tool_metadata::ToolMetadata;
    use xai_tool_runtime::Tool;

    #[test]
    fn control_tools_have_stable_ids() {
        assert_eq!(Tool::id(&ListAgentsTool).as_str(), "list_subagents");
        assert_eq!(Tool::id(&SendMessageTool).as_str(), "send_subagent_message");
        assert_eq!(Tool::id(&FollowupTaskTool).as_str(), "followup_subagent");
        assert_eq!(Tool::id(&InterruptAgentTool).as_str(), "interrupt_subagent");
        assert!(ToolMetadata::description_template(&FollowupTaskTool).contains("resumed"));
    }
}

macro_rules! dynamic_tool_io {
    ($input:ty, $output:ty) => {
        impl From<$input> for crate::types::tool_io::ToolInput {
            fn from(value: $input) -> Self {
                Self::Dynamic(
                    serde_json::to_value(value).expect("Ultra control input must serialize"),
                )
            }
        }

        impl From<$output> for crate::types::output::ToolOutput {
            fn from(value: $output) -> Self {
                Self::Dynamic(
                    serde_json::to_value(value)
                        .expect("Ultra control output must serialize")
                        .into(),
                )
            }
        }
    };
}

dynamic_tool_io!(ListAgentsInput, ListAgentsOutput);
dynamic_tool_io!(SendMessageInput, SendMessageOutput);
dynamic_tool_io!(FollowupTaskInput, FollowupTaskOutput);
dynamic_tool_io!(InterruptAgentInput, InterruptAgentOutput);
