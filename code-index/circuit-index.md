# circuit code index (generated 2026-10-28 from origin/CIRCUIT_KB_STAGING @ dd72d941a6)
Facts derived from the code. Use it to explain a symptom and name the likely area. It is a hint: the worker must verify against the code.

## Controllers (source/worker/com/qntrl/circuit/controller) -> bean / handler they use, public HTTP methods
- ActionsController: bean ActionBean handlers ActionHandler methods index,create,show,update,destroy
- AdminController: bean AdminBean handlers CircuitHandler,FunctionHandler methods circuit,function,execution,processData,resumeData
- AzureController: bean IntegrationBean handlers ExternalIntegrationHandler methods index,create,show,update,destroy,authorize,getVmOptions
- BulkRequestController:  methods 
- CircuitExecutionsController: bean SystemLogBean methods index,create,show,update,destroy
- CircuitValidateController: bean CircuitBean handlers CircuitHandler methods index,create,show,update,destroy
- CircuitVersionsController: bean CircuitVersionBean handlers CircuitHandler methods index,create,show,update,destroy
- CircuitsController: bean CircuitBean handlers CircuitHandler,CredentialHandler methods index,create,show,update,destroy
- ClientConfigurationsController:  methods index,create,show,update,destroy
- CliqController: bean IntegrationBean handlers CliqHandler methods index,create,show,update,destroy
- CredentialsController: bean CredentialBean handlers CredentialHandler methods index,create,show,update,destroy
- DebugController: bean DebugBean handlers FlowHandler,WorkerDataMigrationHandler methods index,create,show,update,destroy
- DeepJsonParserController: bean JsonBean methods index,create,show,update,destroy
- DreConnectionsController: handlers DelugeFunctionHandler methods index,create,show,update,destroy
- EmailTemplatesController: bean EmailTemplateBean handlers EmailTemplateHandler methods index,create,show,update,destroy
- ExecutionsController: bean SystemLogBean handlers CircuitHandler,ExecutionHandler methods index,create,show,update,resumeExecution,destroy
- ExternalIntegrationsController: bean IntegrationBean handlers ExternalIntegrationHandler methods index,create,show,update,destroy
- FunctionsController: bean FunctionBean handlers DelugeFunctionHandler,FunctionHandler methods index,create,show,update,destroy
- GoogleController: bean IntegrationBean handlers ExternalIntegrationHandler methods index,create,show,update,destroy
- IntegrateController: bean IntegrateBean handlers IntegrationResourceAssociationHandler methods index,create,show,update,destroy
- IntegratedUserBulkController: bean UserBulkBean handlers IntegratedUserHandler methods create
- IntegratedUsersController: bean UserBean handlers IntegratedUserHandler methods index,create,show,update,destroy
- IntegrationsController: bean IntegrationBean handlers IntegrationHandler methods index,create,show,update,destroy
- JsonPathController: bean JsonBean methods index,create,show,update,destroy
- JsonSchemaController: bean JsonSchemaBean methods index,create,show,update,destroy
- LookupsController: bean LookupBean handlers DRELookupHandler,FlowLookupHandler,LookupHandler methods index,create,show,update,destroy
- MembersController: bean MemberBean handlers MemberHandler methods index,create,show,update,destroy
- MidserverController: bean MidServerBean methods index,create,show,update,destroy
- OktaController: bean IntegrationBean handlers ExternalIntegrationHandler methods index,create,show,update,destroy
- PowerActionsController: bean PowerActionBean handlers PowerActionHandler methods index,create,show,update,destroy
- QntrlFilesController: bean FileBean handlers FileHandler methods index,create,show,update,destroy
- RequestController:  methods 
- ResourceCountController: bean WorkspaceBean handlers ResourceCountHandler methods index,create,show,update,destroy
- ResourceMappingController: bean ResourceBean handlers ResourceMappingHandler methods index,create,show,update,destroy
- ResourceStatesController: bean TaskBean handlers ResourceStateHandler methods index,show,update,destroy,create
- SequentialDataController: bean SequentialDataBean methods index
- StatesController: bean StateBean handlers StateHandler methods index,show,create,update,destroy
- TasksController: bean TaskBean methods index,create,show,update,destroy
- UsersController: bean UserBean handlers UserHandler methods index,create,show,update,destroy
- WebhooksController: bean WebhookBean handlers WebhookHandler methods index,create,show,update,destroy
- WorkerController: bean CircuitBean methods home
- WorkspacesController: bean WorkspaceBean handlers WorkspaceHandler methods index,create,show,update,destroy

## URL entities in security-api.xml (/qntrl/api/v2/{portal}/{workspace}/{entity}[/{id}/{sub-entity}...]). methods in []; '->Controller' only when the entity name equals a controller name
- bridges[G] sub: resource_mapping
- circuits[DGP]->CircuitsController sub: abort,circuit_versions,executions,rerun,resource_mapping,resume_state,retry
- cliq[GP]->CliqController
- credentials[DGP]->CredentialsController sub: resource_mapping
- email_templates[G]->EmailTemplatesController
- executions[G]->ExecutionsController
- functions[DGP]->FunctionsController sub: deploy,execute,gallery,logs,resource_mapping,test
- integrations[DGP]->IntegrationsController
- resource_count[G]->ResourceCountController
- scripts[G] sub: resource_mapping
- sequential_data[G]->SequentialDataController
- transition[G]
- variables[G] sub: resource_mapping
- webhooks[G]->WebhooksController sub: resource_mapping
- workspaces[DGP]->WorkspacesController
(Sub-entities such as executions/rerun are served by the controller of the last entity: CustomActionMapper turns the entity name into a lower-hyphen action name. Other security-*.xml files are _admin, _internal, _mcp, _tool, _web.)

## Worker layers (names only)
- Handlers (handler): ActionHandler, BulkEntityHandler, CircuitHandler, CircuitLookupHandler, CliqHandler, CredentialHandler, DRELookupHandler, EmailTemplateHandler, EntityHandler, ExecutionHandler, ExternalIntegrationHandler, FileHandler, FlowLookupHandler, FunctionHandler, IntegratedUserHandler, IntegrationHandler, IntegrationResourceAssociationHandler, LookupHandler, MemberHandler, MessageOptions, PowerActionHandler, ResourceCountHandler, ResourceMappingHandler, ResourceStateHandler, StateHandler, UserHandler, WebhookHandler, WorkspaceHandler
- Request beans (bean/request): ActionBean, Actionable, AdminBean, AzureBean, BulkBean, BulkSearchable, CircuitBean, CircuitVersionBean, CredentialBean, DREConnectionBean, DebugBean, DefaultBean, EmailTemplateBean, EntityBean, EntitySearchable, EntitySortable, ExecutionBean, ExternalIntegrationBean, FileBean, FunctionBean, Indexable, IntegrateBean, IntegrationBean, JsonBean, JsonMaskerBean, JsonSchemaBean, LogBean, LookupBean, MemberBean, MidServerBean, PowerActionBean, QntrlRequestController, ResourceBean, SchemaBean, Searchable, SearchableCriteria, SequentialDataBean, Sortable, StateBean, SystemLogBean, TaskBean, UserBean, UserBulkBean, WebhookBean, WorkspaceBean
- Transaction beans (bean/transaction): ActionInvocationBean, ActionInvocationBeanImpl, ExecutionFilesInfo, NoTransactionProcess, NoTransactionProcessBean, WorkerProcess, WorkerProcessBean
- DB access/datasets (db): CircuitBridgeDataSet, CircuitCredentialDataSet, CircuitDataSet, CircuitResourceDataSet, CircuitScriptDataSet, CircuitVariableDataSet, EntityAdapter, ExecutionDataAccess, PredicateAdapter, ResourceCountDataAccess, WorkerDataAccess
- Graph/validation (graph): CircuitConfigurationValidator, CircuitGraph, CircuitTemplateRule, CircuitTraversal, ExecutionValidator, FiniteStateMachine, PlaceholderValidator, StateMachineRule, StateMachineValidator, StateTraversalValidator, Transition
- Utils (util): AiAgentPermissionUtil, AuthorizationProcess, CircuitReplaceUtil, CollectionProcess, CriteriaQueryParser, CustomPredicate, DatasetUtil, DateTimeUtil, DateUtil, DuplicateFinder, DynamicComparator, EntityUtil, IOHelper, JsonPathUtil, ObjectHelper, ParserUtil, PortalServiceUtil, QCZFSUtil, QntrlVariableUtil, RegexRuleUtil, SUUID, ScopeNormalizer, ServiceOrgUtil, StoreWrapper, TaskUtil, TransMailData, WebUtil
- Responses (response): ActionResponse, ActionResponseList, ActorDataResponse, ActorDataResponseList, BulkProcessedResponse, CircuitResponse, CircuitResponseList, CloudFunctionExecutionResponse, CredentialResponse, CredentialResponseList, DelugeFunctionExecutionResponse, EmailTemplateResponse, EmailTemplateResponseList, ErrorResponse, EventLogInfoResponse, EventLogResponse, EventLogResponseList, ExecutionResponse, ExecutionResponseList, FileResponse, FileResponseList, FunctionExecutionResponse, FunctionResponse, FunctionResponseList, HttpResponse, IntegratedResourceResponse, IntegratedResourceResponseList, IntegrationResponse, IntegrationResponseList, IntegrationStatusResponse, LookupResponse, LookupResponseList, MedServerResponseList, MidServerResponse, PowerActionResponse, PowerActionResponseList, QntrlFunctionExecutionResponse, ResourceCountResponse, ResourceMappingResponse, ResourceResponse, ResourceResponseList, Response, ResponseList, ServiceResponse, ServiceResponseList, StateResponse, StateResponseList, TaskResponse, TaskResponseList, TransitionLogResponse, TransitionLogResponseList, UserResponse, UserResponseList, VersionResponse, VersionResponseList, WebhookResponse, WebhookResponseList, WorkspaceResponse, WorkspaceResponseList
- Integrations (integration/): catalyst, cloud, crm, dc, dre, flow, logs360cloud, mail, reactor, sdp

## Executor (source/executor/com/qntrl/execution)
- actor: APIActor, ActionActor, BatchActor, BranchActor, BridgeActor, CRMWebhookActor, Callback, CatalystCustomFunctionActor, CrmCustomFunctionActor, CustomWebhookActor, EmailActor, EndActor, FailureActor, FunctionActor, LinearActor, OnPremiseCustomFunctionActor, ParallelActor, PassActor, PowerActionActor, ProcessActor, Processor, SequentialActor, SeriesActor, SkipActor, StateActor, SuccessActor, TaskActor, TopLinearActor, WaitActor, WebhookActor, ZsoidInjectedSdkAsyncCallback
- task: ActionTask, BatchTask, BranchTask, BridgeTask, CRMWebhookTask, CircuitTask, CustomActionTask, CustomFunctionTask, CustomResourceTask, CustomWebhookTask, EmailTask, EndTask, FailureTask, FunctionTask, OnPremiseCustomFunctionTask, ParallelTask, PassTask, PowerActionTask, QCTask, ResourceTask, SequentialExecutable, SequentialTask, SequentialTaskAdapter, SeriesTask, SkipTask, StateTask, SuccessTask, TailTask, TaskTask, TopLinearTask, WaitTask, WebhookTask
- handler: ActorHandleable, CircuitCallBack, EventLoggable, ExecutorHandler, GetTask, StateCallBack

## Existing unit tests (test/): a class named like its subject
bean.request.SchemaBeanBulkQueryTest, config.TaskConfigurationValidationTest, constant.PlatformAiStateVisibilityTest, constant.RollbackUnsupportedTypesTest, context.ConditionCompilerTest, context.ConditionTest, context.DeepScanTest, context.InlineFilterTest, context.JsonPathTest, context.PathCompilerTest, context.WriteTest, controller.ResourceStatePaletteTransformTest, controller.ResourceStateTransformTest, graph.CircuitTraversalRollbackTest, graph.SqlPlaceholderValidationTest, integration.TaskResourceMappingTest, jsonmasker.JsonMaskerTest, jsonmasker.JsonPathPolicyTrieTest, schema.JsonSchemaDataValidationTest, schema.JsonSchemaDefaultApplierTest, schema.JsonSchemaJsonPathCompositionTest, schema.JsonSchemaResolverTest, schema.JsonSchemaUtilsCheckSchemaTest, schema.JsonSchemaUtilsTest, schema.SchemaDrivenTest, util.CircuitReplaceUtilTest, util.CriteriaQueryParserTest, util.EntityUtilTest, util.JsonPathMirrorTest, util.JsonPathUtilTest, util.ParserUtilTest, util.ScopeNormalizerTest, com.qntrl.execution.edi.CustomDescriptorTest, com.qntrl.execution.edi.DescriptorLintTest, com.qntrl.execution.edi.DescriptorSmokeTest, com.qntrl.execution.edi.EngineTest, com.qntrl.execution.util.FileExtensionValidatorTest
Everything not listed has no unit test: a fix there needs a new test or the human dev test.

## High-risk files (risk: high if touched)
- product_package/conf/Security/QntrlCircuit/security-admin.xml
- product_package/conf/Security/QntrlCircuit/security-api.xml
- product_package/conf/Security/QntrlCircuit/security-internal.xml
- product_package/conf/Security/QntrlCircuit/security-jsontemplate.xml
- product_package/conf/Security/QntrlCircuit/security-mcp.xml
- product_package/conf/Security/QntrlCircuit/security-proxies.xml
- product_package/conf/Security/QntrlCircuit/security-regex.xml
- product_package/conf/Security/QntrlCircuit/security-rule.xml
- product_package/conf/Security/QntrlCircuit/security-tool.xml
- product_package/conf/Security/QntrlCircuit/security-web-client.xml
- product_package/conf/Security/QntrlCircuit/security-web.xml
- product_package/conf/Circuit/data-dictionary-execution.xml
- product_package/conf/Circuit/data-dictionary-resource.xml
- product_package/conf/Circuit/data-dictionary.xml
- product_package/conf/circuit.conf
- product_package/conf/executor.conf
- product_package/conf/integration.conf
- product_package/conf/Circuit/bean.xml
- source/executor/com/qntrl/execution/handler/ActorHandleable.java, ExecutorHandler.java (used by every actor)
- source/entity/** is generated from the data dictionary: never edited by hand

## Symptom -> where to look first
- API returns wrong/missing field in a list or show response: the controller's bean (request) and the handler; for responses see response/.
- 400/409 validation error text or code: exception/ErrorResponseType.java and the handler that throws ValidationException.
- URL not found / 404 / scope or permission: product_package/conf/Security/QntrlCircuit/security-api.xml (high risk) and CustomActionMapper (source/qntrl/com/qntrl/struts).
- Execution stuck/failed at a state: executor/actor/* and executor/task/*; state definition in worker state/ and graph/.
- Placeholder / ${...} substitution: substitutor/QntrlSubstitutor and graph/PlaceholderValidator.
