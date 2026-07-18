import type { Component } from 'vue';
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
    // Loaded via import.meta.glob rather than a direct dynamic import so
    // TypeScript doesn't follow the reference: design-lab is untyped scratch
    // space, excluded from type checking (tsconfig.app.json) and lint
    // (eslint.config.js) so its experiments can't redden the real gates.
    path: '/design-lab/:slug/:n?',
    component: Object.values(
      import.meta.glob<{ default: Component }>('./design-lab/LabRouter.vue'),
    )[0]!,
  },
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
});
