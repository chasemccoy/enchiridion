import AddRecordView from '@app/views/AddRecordView.vue';
import ArtifactsView from '@app/views/ArtifactsView.vue';
import ConceptsView from '@app/views/ConceptsView.vue';
import EntitiesView from '@app/views/EntitiesView.vue';
import InboxView from '@app/views/InboxView.vue';
import IndexV2View from '@app/views/IndexV2View.vue';
import IndexView from '@app/views/IndexView.vue';
import RecordDetailView from '@app/views/RecordDetailView.vue';
import RecordTableView from '@app/views/RecordTableView.vue';
import SearchView from '@app/views/SearchView.vue';
import { createWebHistory, createRouter } from 'vue-router';

export enum RouteName {
  index = 'index',
  indexV2 = 'indexV2',
  inbox = 'inbox',
  records = 'records',
  artifacts = 'artifacts',
  concepts = 'concepts',
  entities = 'entities',
  search = 'search',
  add = 'add',
}

const routes = [
  {
    path: '/',
    name: RouteName.index,
    component: IndexView,
    children: [
      {
        path: ':slug',
        component: RecordDetailView,
      },
    ],
  },
  {
    path: '/inbox',
    name: RouteName.inbox,
    component: InboxView,
    children: [
      {
        path: 'record/:slug',
        component: RecordDetailView,
      },
    ],
  },
  {
    path: '/v2',
    name: RouteName.indexV2,
    component: IndexV2View,
    children: [
      {
        path: ':slug',
        component: RecordDetailView,
      },
    ],
  },
  {
    path: '/records',
    name: RouteName.records,
    component: RecordTableView,
  },
  {
    path: '/artifacts',
    name: RouteName.artifacts,
    component: ArtifactsView,
  },
  {
    path: '/concepts',
    name: RouteName.concepts,
    component: ConceptsView,
  },
  {
    path: '/entities',
    name: RouteName.entities,
    component: EntitiesView,
  },
  {
    path: '/search',
    name: RouteName.search,
    component: SearchView,
  },
  {
    path: '/add',
    name: RouteName.add,
    component: AddRecordView,
  },
  {
    // Design lab — scratch playground for layout exploration. Not for prod.
    path: '/design-lab/:slug/:n?',
    component: () => import('@app/design-lab/LabRouter.vue'),
  },
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
});
