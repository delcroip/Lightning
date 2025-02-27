import { Lightning, Flow, Positions } from '../types';
import { sortOrderForSvg, styleEdge, styleItem, styleNode } from '../styles';

function getEdgeLabel(condition: string) {
  if (condition) {
    if (condition === 'on_job_success') {
      return '✓';
    }
    if (condition === 'on_job_failure') {
      return 'X';
    }
    if (condition === 'always') {
      return '∞';
    }
  }
  // some code expression
  return '{}';
}

const fromWorkflow = (
  workflow: Lightning.Workflow,
  positions: Positions,
  placeholders: Flow.Model = { nodes: [], edges: [] },
  selectedId?: string
): Flow.Model => {
  const allowPlaceholder = placeholders.nodes.length === 0;

  const process = (
    items: Array<Lightning.Node | Lightning.Edge>,
    collection: Array<Flow.Node | Flow.Edge>,
    type: 'job' | 'trigger' | 'edge'
  ) => {
    items.forEach(item => {
      const model: any = {
        id: item.id,
        data: {
          ...item,
        },
      };

      if (item.id === selectedId) {
        model.selected = true;
      } else {
        model.selected = false;
      }

      if (/(job|trigger)/.test(type)) {
        const node = item as Lightning.Node;
        model.type = type;

        if (positions && positions[node.id]) {
          model.position = positions[node.id];
        }

        model.data.allowPlaceholder = allowPlaceholder;

        if (type === 'trigger') {
          console.log('trigger model', item);
          model.data.trigger = {
            type: (node as Lightning.TriggerNode).type,
            enabled: (node as Lightning.TriggerNode).enabled,
          };
        }
        styleNode(model);
      } else {
        const edge = item as Lightning.Edge;
        model.source = edge.source_trigger_id || edge.source_job_id;
        model.target = edge.target_job_id;
        model.type = 'step';
        model.label = getEdgeLabel(edge.condition);
        model.markerEnd = {
          type: 'arrowclosed',
          width: 32,
          height: 32,
        };
        model.data = { condition: edge.condition, enabled: edge.enabled };

        // Note: we don't allow the user to disable the edge that goes from a
        // trigger to a job, but we want to show it as if it were disabled when
        // the source trigger is disabled. This code does that.
        const source = nodes.find(x => x.id == model.source);
        if (source.type == 'trigger') {
          model.data.enabled = source?.data.enabled;
        }

        styleEdge(model);
      }

      collection.push(model);
    });
  };

  const nodes = [
    ...placeholders.nodes.map(n => {
      if (selectedId == n.id) {
        n.selected = true;
      }
      return styleNode(n);
    }),
  ] as Flow.Node[];

  const edges = [...placeholders.edges.map(e => styleEdge(e))] as Flow.Edge[];

  process(workflow.jobs, nodes, 'job');
  process(workflow.triggers, nodes, 'trigger');
  process(workflow.edges, edges, 'edge');

  const sortedEdges = edges.sort(sortOrderForSvg);

  return { nodes, edges: sortedEdges };
};

export default fromWorkflow;
