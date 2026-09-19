import unittest
from backend import minimize_command, workspace_command
class WorkspaceTests(unittest.TestCase):
    def command(self,current,direction,extra=()):
        monitors=[{'name':'eDP-1','activeWorkspace':{'id':current}},
                  {'name':'eDP-2','activeWorkspace':{'id':2},'focused':True}]
        workspaces=[{'id':current,'monitor':'eDP-1'},{'id':2,'monitor':'eDP-2'},*extra]
        return workspace_command(direction,monitors,workspaces)
    def test_next_skips_keyboard_and_focuses_upper_first(self):
        result=self.command(1,'next')
        self.assertEqual(result[:2],['hyprctl','eval'])
        self.assertIn('workspace = "3"',result[2])
        self.assertLess(result[2].index('monitor = "eDP-1"'),result[2].index('workspace'))
    def test_previous_and_wrap(self):
        for current,direction,target in [(3,'previous',1),(1,'previous',10),(10,'next',1)]:
            self.assertIn(f'workspace = "{target}"',self.command(current,direction)[2])
    def test_other_monitor_workspace_is_not_stolen(self):
        self.assertIn('workspace = "5"',self.command(3,'next',[{'id':4,'monitor':'HDMI-A-1'}])[2])
    def test_disconnected_upper_does_not_change_lower(self):
        with self.assertRaises(ValueError):workspace_command('next',[],[])
    def test_invalid_direction(self):
        with self.assertRaises(ValueError):workspace_command('bad',[],[])
    def test_minimize_targets_upper_screen(self):
        self.assertEqual(minimize_command('down'),['hyprctl','eval','require("hypr.minimize").minimize_all("eDP-1")'])
        self.assertIn('restore_all("eDP-1")',minimize_command('up')[2])
        with self.assertRaises(ValueError):minimize_command('sideways')
if __name__=='__main__': unittest.main()
