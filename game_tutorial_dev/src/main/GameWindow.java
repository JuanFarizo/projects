package main;

import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;

import javax.swing.JFrame;

public class GameWindow {
    private JFrame jFrame;
    public GameWindow(GamePanel gamePanel) {
        this.jFrame = new JFrame();
        jFrame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        jFrame.add(gamePanel);
        jFrame.setLocationRelativeTo(null);
        jFrame.setResizable(false);
        jFrame.pack();
        jFrame.setVisible(true);
        jFrame.addWindowFocusListener(new WindowAdapter() {
            @Override
            public void windowLostFocus(WindowEvent e) {
                gamePanel.getGame().windowFocusLost();
            }

            @Override
            public void windowGainedFocus(WindowEvent e) {
                super.windowGainedFocus(e);
            }
        });
    }
}
