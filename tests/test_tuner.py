import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('tuner', Path(__file__).resolve().parents[1] / 'tuner/tuner.py')
tuner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tuner)


class TunerTests(unittest.TestCase):
    def test_off_removes_all_managed_terminal_overrides(self):
        state = tuner.defaults()
        user = '[main]\nfont=User Font:size=11\npad=14x14\n[colors-dark]\nalpha=0.9\n'
        glass = tuner.write_foot(state, user)
        state['glass_on'] = False
        self.assertEqual(tuner.write_foot(state, glass), user)

    def test_off_does_not_override_theme_borders_or_animations(self):
        state = tuner.defaults()
        state.update(glass_on=False, border_spin=True, glass_border=False)
        self.assertEqual(tuner.look_lua(state), '')
        self.assertIn('materialize_duration = 0.0', tuner.light_lua(state))

    def test_off_restores_included_theme_and_user_alpha(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            theme = Path(directory) / 'theme.ini'
            theme.write_text('[colors-dark]\nforeground=aabbcc\nbackground=112233\nalpha=0.8\n')
            foot = Path(directory) / 'foot.ini'
            base = f'[main]\ninclude={theme}\n[colors-dark]\nalpha=0.9\n'
            foot.write_text(tuner.write_foot(tuner.defaults(), base))
            with patch.object(tuner, 'FOOT_INI', str(foot)):
                self.assertEqual(tuner.base_foot_colors(), (0.9, 'aabbcc', '112233'))

    def test_off_syncs_original_colours_instead_of_glass_transparency(self):
        state = tuner.defaults()
        state.update(glass_on=False, foot_alpha=0.25, text_boost=1)
        with patch.object(tuner, 'base_foot_colors', return_value=(1, 'aabbcc', '112233')), patch.object(tuner, 'push_foot_alpha') as alpha, patch.object(tuner, 'push_foot_text') as text:
            tuner.sync_foot(state, force=True)
        alpha.assert_called_once_with(1, '112233')
        text.assert_called_once_with(0, 'aabbcc')

    def test_power_persists_only_switch_and_keeps_preview(self):
        saved = {'glass_on': True, 'blur_strength': 0.2}
        preview = {'glass_on': True, 'blur_strength': 0.8}
        with patch.object(tuner, 'load_state', return_value=saved.copy()), patch.object(tuner, 'save', return_value='') as save, patch.object(tuner, 'apply') as apply:
            result = tuner.set_power(False, preview)
        save.assert_called_once_with({'glass_on': False, 'blur_strength': 0.2})
        apply.assert_called_once_with({'glass_on': False, 'blur_strength': 0.8})
        self.assertFalse(result['enabled'])

    def test_power_rejects_non_boolean(self):
        with patch.object(tuner, 'save') as save:
            for enabled in (None, 0, 1, 'false'):
                with self.assertRaises(ValueError):
                    tuner.set_power(enabled, {})
            save.assert_not_called()

    def test_native_panel_apply_keeps_compare_flag(self):
        state = tuner.clean({'glass_on': True, 'blur_strength': 0.7})
        with patch.object(tuner, 'apply') as apply:
            tuner.panel_action({'action': 'apply', 'state': state, 'compare': True})
        apply.assert_called_once_with(state, preview_off=True)

    def test_native_panel_rejects_unknown_action(self):
        with self.assertRaises(ValueError):
            tuner.panel_action({'action': 'shell-command'})

    def test_native_panel_preserves_all_original_controls(self):
        import json
        controls = json.loads((Path(__file__).resolve().parents[1] / 'tuner/controls.json').read_text())
        keys = set()
        for section in controls['sections']:
            keys.update(row[0] for row in section.get('rows', []))
            keys.update(row[0] for row in section.get('toggles', []))
            keys.update(row[0] for row in section.get('choices', []))
            if section.get('extra'):
                keys.add(section['extra'][0])
            if section.get('action'):
                keys.add(section['action'])
        self.assertTrue(keys.issubset(tuner.defaults()))
        self.assertIn('materialize_duration', keys)
        self.assertIn('font_weight', keys)
        self.assertIn('tint', keys)



if __name__ == '__main__':
    unittest.main()
