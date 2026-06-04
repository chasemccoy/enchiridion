import IndexView from '@app/views/IndexView.vue';
import RecordDetailView from '@app/views/RecordDetailView.vue';
import { createWebHistory, createRouter } from 'vue-router';

const AddRecordView = () => import('@app/views/AddRecordView.vue');
const ArtifactsView = () => import('@app/views/ArtifactsView.vue');
const ConceptsView = () => import('@app/views/ConceptsView.vue');
const EntitiesView = () => import('@app/views/EntitiesView.vue');
const InboxView = () => import('@app/views/InboxView.vue');
const RecordTableView = () => import('@app/views/RecordTableView.vue');
const SearchView = () => import('@app/views/SearchView.vue');

export enum RouteName {
  index = 'index',
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
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
});
