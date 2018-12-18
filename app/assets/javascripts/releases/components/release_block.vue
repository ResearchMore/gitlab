<script>
import { GlTooltipDirective, GlLink } from '@gitlab/ui';
import Icon from '~/vue_shared/components/icon.vue';
import UserAvatarLink from '~/vue_shared/components/user_avatar/user_avatar_link.vue';
import timeagoMixin from '~/vue_shared/mixins/timeago';
import { sprintf } from '../../locale';

export default {
  name: 'ReleaseBlock',
  components: {
    GlLink,
    Icon,
    UserAvatarLink,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [timeagoMixin],
  props: {
    name: {
      type: String,
      required: true,
    },
    tag: {
      type: String,
      required: true,
    },
    commit: {
      type: Object,
      required: true,
    },
    description: {
      type: String,
      required: false,
      default: '',
    },
    author: {
      type: Object,
      required: true,
    },
    createdAt: {
      type: String,
      required: false,
      default: '',
    },
    assetsCount: {
      type: Number,
      required: false,
      default: 0,
    },
    sources: {
      type: Array,
      required: false,
      default: () => [],
    },
    links: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  computed: {
    releasedTimeAgo() {
      return sprintf('released %{time}', {
        time: this.timeFormated(this.createdAt),
      });
    },
    userImageAltDescription() {
      return this.author && this.author.username
        ? sprintf("%{username}'s avatar", { username: this.author.username })
        : null;
    },
  },
};
</script>
<template>
  <div class="card">
    <div class="card-body">
      <h2 class="card-title mt-0">{{ name }}</h2>

      <div class="card-subtitle d-flex flex-wrap text-secondary">
        <div class="append-right-8">
          <icon name="commit" class="align-middle" />
          <span v-gl-tooltip.bottom :title="commit.title">{{ commit.short_id }}</span>
        </div>

        <div class="append-right-8">
          <icon name="tag" class="align-middle" />
          <span v-gl-tooltip.bottom :title="__('Tag')">{{ tag }}</span>
        </div>

        <div class="append-right-4">
          &bull;
          <span v-gl-tooltip.bottom :title="tooltipTitle(createdAt)">{{ releasedTimeAgo }}</span>
        </div>

        <div class="d-flex">
          by
          <user-avatar-link
            class="prepend-left-4"
            :link-href="author.path"
            :img-src="author.avatar_url"
            :img-alt="userImageAltDescription"
            :tooltip-text="author.username"
          />
        </div>
      </div>

      <div class="card-text prepend-top-default">
        <b>
          {{ __('Assets') }} <span class="js-assets-count badge badge-pill">{{ assetsCount }}</span>
        </b>

        <ul class="pl-0 mb-0 prepend-top-8 list-unstyled js-assets-list">
          <li v-for="link in links" :key="link.name" class="append-bottom-8">
            <gl-link v-gl-tooltip.bottom :title="__('Download asset')" :href="link.url">
              <icon name="package" class="align-middle append-right-4" /> {{ link.name }}
            </gl-link>
          </li>
        </ul>

        <div class="dropdown">
          <button
            type="button"
            class="btn btn-link"
            data-toggle="dropdown"
            aria-haspopup="true"
            aria-expanded="false"
          >
            <icon name="doc-code" class="align-top append-right-4" /> {{ __('Source code') }}
            <icon name="arrow-down" />
          </button>

          <div class="js-sources-dropdown dropdown-menu">
            <li v-for="asset in sources" :key="asset.url">
              <gl-link :href="asset.url">{{ __('Download') }} {{ asset.format }}</gl-link>
            </li>
          </div>
        </div>
      </div>

      <div class="card-text prepend-top-default"><div v-html="description"></div></div>
    </div>
  </div>
</template>