import AddRecordView from '@app/views/AddRecordView.vue';
import ArtifactsView from '@app/views/ArtifactsView.vue';
import ConceptsView from '@app/views/ConceptsView.vue';
import EntitiesView from '@app/views/EntitiesView.vue';
import IndexView from '@app/views/IndexView.vue';
import RecordDetailView from '@app/views/RecordDetailView.vue';
import { createWebHistory, createRouter, type RouteRecordRaw } from 'vue-router';

export enum RouteName {
  index = 'index',
  artifacts = 'artifacts',
  concepts = 'concepts',
  entities = 'entities',
  add = 'add',
}

const routes: RouteRecordRaw[] = [
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
