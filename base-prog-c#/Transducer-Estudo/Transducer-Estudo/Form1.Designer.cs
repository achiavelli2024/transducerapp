namespace Transducer_Estudo
{
    partial class Form1
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            this.drpPortName = new System.Windows.Forms.ComboBox();
            this.label3 = new System.Windows.Forms.Label();
            this.button2 = new System.Windows.Forms.Button();
            this.timer1 = new System.Windows.Forms.Timer(this.components);
            this.btnReadData = new System.Windows.Forms.Button();
            this.label12 = new System.Windows.Forms.Label();
            this.label11 = new System.Windows.Forms.Label();
            this.label10 = new System.Windows.Forms.Label();
            this.txtTimeoutEnd = new System.Windows.Forms.TextBox();
            this.txtThresholdEnd = new System.Windows.Forms.TextBox();
            this.txtThresholdIni = new System.Windows.Forms.TextBox();
            this.lblTorque1 = new System.Windows.Forms.Label();
            this.lblAngulo1 = new System.Windows.Forms.Label();
            this.label8 = new System.Windows.Forms.Label();
            this.lblTorque = new System.Windows.Forms.Label();
            this.label9 = new System.Windows.Forms.Label();
            this.lblAngulo = new System.Windows.Forms.Label();
            this.label14 = new System.Windows.Forms.Label();
            this.label13 = new System.Windows.Forms.Label();
            this.lblUntighteningsCounter = new System.Windows.Forms.Label();
            this.lblResultsCounter = new System.Windows.Forms.Label();
            this.button3 = new System.Windows.Forms.Button();
            this.lblUpdateTorqueSpan = new System.Windows.Forms.Label();
            this.lblUpdateTorque = new System.Windows.Forms.Label();
            this.btnDisconnect2 = new System.Windows.Forms.Button();
            this.btnConnectIP = new System.Windows.Forms.Button();
            this.label28 = new System.Windows.Forms.Label();
            this.txtIP = new System.Windows.Forms.TextBox();
            this.txtIndex = new System.Windows.Forms.TextBox();
            this.btnDisconnect = new System.Windows.Forms.Button();
            this.label7 = new System.Windows.Forms.Label();
            this.txtTimeoutFree = new System.Windows.Forms.TextBox();
            this.label6 = new System.Windows.Forms.Label();
            this.label5 = new System.Windows.Forms.Label();
            this.label4 = new System.Windows.Forms.Label();
            this.txtThresholdEndFree = new System.Windows.Forms.TextBox();
            this.label15 = new System.Windows.Forms.Label();
            this.txtThresholdIniFree = new System.Windows.Forms.TextBox();
            this.label16 = new System.Windows.Forms.Label();
            this.txtMaximoTorque = new System.Windows.Forms.TextBox();
            this.txtNominalTorque = new System.Windows.Forms.TextBox();
            this.txtMinimumTorque = new System.Windows.Forms.TextBox();
            this.SuspendLayout();
            // 
            // drpPortName
            // 
            this.drpPortName.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.drpPortName.FormattingEnabled = true;
            this.drpPortName.Location = new System.Drawing.Point(133, 15);
            this.drpPortName.Margin = new System.Windows.Forms.Padding(4);
            this.drpPortName.Name = "drpPortName";
            this.drpPortName.Size = new System.Drawing.Size(160, 24);
            this.drpPortName.TabIndex = 6;
            // 
            // label3
            // 
            this.label3.Location = new System.Drawing.Point(13, 13);
            this.label3.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(98, 28);
            this.label3.TabIndex = 5;
            this.label3.Text = "Port Name:";
            this.label3.TextAlign = System.Drawing.ContentAlignment.MiddleRight;
            // 
            // button2
            // 
            this.button2.Location = new System.Drawing.Point(446, 2);
            this.button2.Name = "button2";
            this.button2.Size = new System.Drawing.Size(122, 37);
            this.button2.TabIndex = 7;
            this.button2.Text = "Connect";
            this.button2.UseVisualStyleBackColor = true;
            this.button2.Click += new System.EventHandler(this.button2_Click);
            // 
            // btnReadData
            // 
            this.btnReadData.Location = new System.Drawing.Point(419, 168);
            this.btnReadData.Margin = new System.Windows.Forms.Padding(4);
            this.btnReadData.Name = "btnReadData";
            this.btnReadData.Size = new System.Drawing.Size(149, 48);
            this.btnReadData.TabIndex = 16;
            this.btnReadData.Text = "Set PSet + Start";
            this.btnReadData.UseVisualStyleBackColor = true;
            this.btnReadData.Click += new System.EventHandler(this.btnReadData_Click);
            // 
            // label12
            // 
            this.label12.AutoSize = true;
            this.label12.Location = new System.Drawing.Point(588, 213);
            this.label12.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label12.Name = "label12";
            this.label12.Size = new System.Drawing.Size(76, 16);
            this.label12.TabIndex = 53;
            this.label12.Text = "end timeout";
            // 
            // label11
            // 
            this.label11.AutoSize = true;
            this.label11.Location = new System.Drawing.Point(584, 186);
            this.label11.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label11.Name = "label11";
            this.label11.Size = new System.Drawing.Size(88, 16);
            this.label11.TabIndex = 52;
            this.label11.Text = "threshold end";
            // 
            // label10
            // 
            this.label10.AutoSize = true;
            this.label10.Location = new System.Drawing.Point(588, 164);
            this.label10.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label10.Name = "label10";
            this.label10.Size = new System.Drawing.Size(78, 16);
            this.label10.TabIndex = 51;
            this.label10.Text = "threshold ini";
            // 
            // txtTimeoutEnd
            // 
            this.txtTimeoutEnd.Location = new System.Drawing.Point(680, 207);
            this.txtTimeoutEnd.Margin = new System.Windows.Forms.Padding(4);
            this.txtTimeoutEnd.Name = "txtTimeoutEnd";
            this.txtTimeoutEnd.Size = new System.Drawing.Size(56, 22);
            this.txtTimeoutEnd.TabIndex = 50;
            this.txtTimeoutEnd.Text = "400";
            // 
            // txtThresholdEnd
            // 
            this.txtThresholdEnd.Location = new System.Drawing.Point(680, 183);
            this.txtThresholdEnd.Margin = new System.Windows.Forms.Padding(4);
            this.txtThresholdEnd.Name = "txtThresholdEnd";
            this.txtThresholdEnd.Size = new System.Drawing.Size(56, 22);
            this.txtThresholdEnd.TabIndex = 49;
            this.txtThresholdEnd.Text = "0.5";
            // 
            // txtThresholdIni
            // 
            this.txtThresholdIni.Location = new System.Drawing.Point(680, 160);
            this.txtThresholdIni.Margin = new System.Windows.Forms.Padding(4);
            this.txtThresholdIni.Name = "txtThresholdIni";
            this.txtThresholdIni.Size = new System.Drawing.Size(56, 22);
            this.txtThresholdIni.TabIndex = 48;
            this.txtThresholdIni.Text = "1";
            // 
            // lblTorque1
            // 
            this.lblTorque1.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            this.lblTorque1.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.lblTorque1.Location = new System.Drawing.Point(180, 246);
            this.lblTorque1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.lblTorque1.Name = "lblTorque1";
            this.lblTorque1.Size = new System.Drawing.Size(79, 28);
            this.lblTorque1.TabIndex = 59;
            this.lblTorque1.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            // 
            // lblAngulo1
            // 
            this.lblAngulo1.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            this.lblAngulo1.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.lblAngulo1.Location = new System.Drawing.Point(180, 217);
            this.lblAngulo1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.lblAngulo1.Name = "lblAngulo1";
            this.lblAngulo1.Size = new System.Drawing.Size(79, 28);
            this.lblAngulo1.TabIndex = 58;
            this.lblAngulo1.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            // 
            // label8
            // 
            this.label8.AutoSize = true;
            this.label8.Location = new System.Drawing.Point(49, 252);
            this.label8.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label8.Name = "label8";
            this.label8.Size = new System.Drawing.Size(54, 16);
            this.label8.TabIndex = 57;
            this.label8.Text = "Torque:";
            // 
            // lblTorque
            // 
            this.lblTorque.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            this.lblTorque.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.lblTorque.Location = new System.Drawing.Point(108, 246);
            this.lblTorque.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.lblTorque.Name = "lblTorque";
            this.lblTorque.Size = new System.Drawing.Size(71, 28);
            this.lblTorque.TabIndex = 56;
            this.lblTorque.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            // 
            // label9
            // 
            this.label9.AutoSize = true;
            this.label9.Location = new System.Drawing.Point(50, 223);
            this.label9.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label9.Name = "label9";
            this.label9.Size = new System.Drawing.Size(45, 16);
            this.label9.TabIndex = 55;
            this.label9.Text = "Angle:";
            // 
            // lblAngulo
            // 
            this.lblAngulo.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            this.lblAngulo.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.lblAngulo.Location = new System.Drawing.Point(108, 217);
            this.lblAngulo.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.lblAngulo.Name = "lblAngulo";
            this.lblAngulo.Size = new System.Drawing.Size(71, 28);
            this.lblAngulo.TabIndex = 54;
            this.lblAngulo.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            // 
            // label14
            // 
            this.label14.AutoSize = true;
            this.label14.Location = new System.Drawing.Point(1001, 37);
            this.label14.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label14.Name = "label14";
            this.label14.Size = new System.Drawing.Size(85, 16);
            this.label14.TabIndex = 63;
            this.label14.Text = "untightenings";
            // 
            // label13
            // 
            this.label13.AutoSize = true;
            this.label13.Location = new System.Drawing.Point(1001, 15);
            this.label13.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label13.Name = "label13";
            this.label13.Size = new System.Drawing.Size(71, 16);
            this.label13.TabIndex = 62;
            this.label13.Text = "tightenings";
            // 
            // lblUntighteningsCounter
            // 
            this.lblUntighteningsCounter.AutoSize = true;
            this.lblUntighteningsCounter.Location = new System.Drawing.Point(1099, 37);
            this.lblUntighteningsCounter.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.lblUntighteningsCounter.Name = "lblUntighteningsCounter";
            this.lblUntighteningsCounter.Size = new System.Drawing.Size(14, 16);
            this.lblUntighteningsCounter.TabIndex = 61;
            this.lblUntighteningsCounter.Text = "0";
            // 
            // lblResultsCounter
            // 
            this.lblResultsCounter.AutoSize = true;
            this.lblResultsCounter.Location = new System.Drawing.Point(1099, 15);
            this.lblResultsCounter.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.lblResultsCounter.Name = "lblResultsCounter";
            this.lblResultsCounter.Size = new System.Drawing.Size(14, 16);
            this.lblResultsCounter.TabIndex = 60;
            this.lblResultsCounter.Text = "0";
            // 
            // button3
            // 
            this.button3.Location = new System.Drawing.Point(419, 224);
            this.button3.Margin = new System.Windows.Forms.Padding(4);
            this.button3.Name = "button3";
            this.button3.Size = new System.Drawing.Size(59, 48);
            this.button3.TabIndex = 64;
            this.button3.Text = "Stop";
            this.button3.UseVisualStyleBackColor = true;
            this.button3.Click += new System.EventHandler(this.button3_Click);
            // 
            // lblUpdateTorqueSpan
            // 
            this.lblUpdateTorqueSpan.AutoSize = true;
            this.lblUpdateTorqueSpan.Location = new System.Drawing.Point(130, 287);
            this.lblUpdateTorqueSpan.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.lblUpdateTorqueSpan.Name = "lblUpdateTorqueSpan";
            this.lblUpdateTorqueSpan.Size = new System.Drawing.Size(14, 16);
            this.lblUpdateTorqueSpan.TabIndex = 66;
            this.lblUpdateTorqueSpan.Text = "0";
            // 
            // lblUpdateTorque
            // 
            this.lblUpdateTorque.AutoSize = true;
            this.lblUpdateTorque.Location = new System.Drawing.Point(207, 287);
            this.lblUpdateTorque.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.lblUpdateTorque.Name = "lblUpdateTorque";
            this.lblUpdateTorque.Size = new System.Drawing.Size(14, 16);
            this.lblUpdateTorque.TabIndex = 65;
            this.lblUpdateTorque.Text = "0";
            // 
            // btnDisconnect2
            // 
            this.btnDisconnect2.Location = new System.Drawing.Point(587, 65);
            this.btnDisconnect2.Margin = new System.Windows.Forms.Padding(4);
            this.btnDisconnect2.Name = "btnDisconnect2";
            this.btnDisconnect2.Size = new System.Drawing.Size(120, 31);
            this.btnDisconnect2.TabIndex = 70;
            this.btnDisconnect2.Text = "Disconnect";
            this.btnDisconnect2.UseVisualStyleBackColor = true;
            this.btnDisconnect2.Click += new System.EventHandler(this.btnDisconnect2_Click);
            // 
            // btnConnectIP
            // 
            this.btnConnectIP.Location = new System.Drawing.Point(446, 66);
            this.btnConnectIP.Margin = new System.Windows.Forms.Padding(4);
            this.btnConnectIP.Name = "btnConnectIP";
            this.btnConnectIP.Size = new System.Drawing.Size(120, 31);
            this.btnConnectIP.TabIndex = 69;
            this.btnConnectIP.Text = "Connect IP";
            this.btnConnectIP.UseVisualStyleBackColor = true;
            this.btnConnectIP.Click += new System.EventHandler(this.btnConnectIP_Click);
            // 
            // label28
            // 
            this.label28.Location = new System.Drawing.Point(89, 66);
            this.label28.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label28.Name = "label28";
            this.label28.Size = new System.Drawing.Size(36, 28);
            this.label28.TabIndex = 68;
            this.label28.Text = "IP:";
            this.label28.TextAlign = System.Drawing.ContentAlignment.MiddleRight;
            // 
            // txtIP
            // 
            this.txtIP.Location = new System.Drawing.Point(133, 69);
            this.txtIP.Margin = new System.Windows.Forms.Padding(4);
            this.txtIP.Name = "txtIP";
            this.txtIP.Size = new System.Drawing.Size(160, 22);
            this.txtIP.TabIndex = 67;
            this.txtIP.Text = "192.168.4.1";
            // 
            // txtIndex
            // 
            this.txtIndex.Location = new System.Drawing.Point(301, 70);
            this.txtIndex.Margin = new System.Windows.Forms.Padding(4);
            this.txtIndex.MaxLength = 1;
            this.txtIndex.Name = "txtIndex";
            this.txtIndex.Size = new System.Drawing.Size(32, 22);
            this.txtIndex.TabIndex = 71;
            this.txtIndex.Text = "0";
            this.txtIndex.WordWrap = false;
            // 
            // btnDisconnect
            // 
            this.btnDisconnect.Location = new System.Drawing.Point(715, 66);
            this.btnDisconnect.Margin = new System.Windows.Forms.Padding(4);
            this.btnDisconnect.Name = "btnDisconnect";
            this.btnDisconnect.Size = new System.Drawing.Size(120, 31);
            this.btnDisconnect.TabIndex = 72;
            this.btnDisconnect.Text = "Disconnect";
            this.btnDisconnect.UseVisualStyleBackColor = true;
            this.btnDisconnect.Click += new System.EventHandler(this.btnDisconnect_Click);
            // 
            // label7
            // 
            this.label7.AutoSize = true;
            this.label7.Font = new System.Drawing.Font("Comic Sans MS", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label7.Location = new System.Drawing.Point(852, 323);
            this.label7.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label7.Name = "label7";
            this.label7.Size = new System.Drawing.Size(133, 28);
            this.label7.TabIndex = 84;
            this.label7.Text = "End Timeout:";
            this.label7.Visible = false;
            // 
            // txtTimeoutFree
            // 
            this.txtTimeoutFree.Font = new System.Drawing.Font("Microsoft Sans Serif", 10F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.txtTimeoutFree.Location = new System.Drawing.Point(1028, 325);
            this.txtTimeoutFree.Margin = new System.Windows.Forms.Padding(4);
            this.txtTimeoutFree.Name = "txtTimeoutFree";
            this.txtTimeoutFree.Size = new System.Drawing.Size(81, 26);
            this.txtTimeoutFree.TabIndex = 83;
            this.txtTimeoutFree.Text = "400";
            this.txtTimeoutFree.TextAlign = System.Windows.Forms.HorizontalAlignment.Center;
            this.txtTimeoutFree.Visible = false;
            // 
            // label6
            // 
            this.label6.AutoSize = true;
            this.label6.Font = new System.Drawing.Font("Comic Sans MS", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label6.Location = new System.Drawing.Point(852, 184);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(162, 28);
            this.label6.TabIndex = 82;
            this.label6.Text = "Torque Maximo:";
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Font = new System.Drawing.Font("Comic Sans MS", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label5.Location = new System.Drawing.Point(852, 94);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(156, 28);
            this.label5.TabIndex = 81;
            this.label5.Text = "Torque Minimo:";
            // 
            // label4
            // 
            this.label4.AutoSize = true;
            this.label4.Font = new System.Drawing.Font("Comic Sans MS", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label4.Location = new System.Drawing.Point(852, 139);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(163, 28);
            this.label4.TabIndex = 80;
            this.label4.Text = "Torque Nominal:";
            // 
            // txtThresholdEndFree
            // 
            this.txtThresholdEndFree.Font = new System.Drawing.Font("Microsoft Sans Serif", 10F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.txtThresholdEndFree.Location = new System.Drawing.Point(1028, 285);
            this.txtThresholdEndFree.Name = "txtThresholdEndFree";
            this.txtThresholdEndFree.Size = new System.Drawing.Size(81, 26);
            this.txtThresholdEndFree.TabIndex = 79;
            this.txtThresholdEndFree.Text = "0.5";
            this.txtThresholdEndFree.TextAlign = System.Windows.Forms.HorizontalAlignment.Center;
            this.txtThresholdEndFree.Visible = false;
            // 
            // label15
            // 
            this.label15.AutoSize = true;
            this.label15.Font = new System.Drawing.Font("Comic Sans MS", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label15.Location = new System.Drawing.Point(852, 283);
            this.label15.Name = "label15";
            this.label15.Size = new System.Drawing.Size(155, 28);
            this.label15.TabIndex = 78;
            this.label15.Text = "Threshold End:";
            this.label15.Visible = false;
            // 
            // txtThresholdIniFree
            // 
            this.txtThresholdIniFree.Font = new System.Drawing.Font("Microsoft Sans Serif", 10F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.txtThresholdIniFree.Location = new System.Drawing.Point(1028, 248);
            this.txtThresholdIniFree.Name = "txtThresholdIniFree";
            this.txtThresholdIniFree.Size = new System.Drawing.Size(81, 26);
            this.txtThresholdIniFree.TabIndex = 77;
            this.txtThresholdIniFree.Text = "2";
            this.txtThresholdIniFree.TextAlign = System.Windows.Forms.HorizontalAlignment.Center;
            // 
            // label16
            // 
            this.label16.AutoSize = true;
            this.label16.Font = new System.Drawing.Font("Comic Sans MS", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label16.Location = new System.Drawing.Point(852, 246);
            this.label16.Name = "label16";
            this.label16.Size = new System.Drawing.Size(171, 28);
            this.label16.TabIndex = 76;
            this.label16.Text = "Threshold Start:";
            // 
            // txtMaximoTorque
            // 
            this.txtMaximoTorque.Font = new System.Drawing.Font("Microsoft Sans Serif", 10F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.txtMaximoTorque.Location = new System.Drawing.Point(1028, 186);
            this.txtMaximoTorque.Name = "txtMaximoTorque";
            this.txtMaximoTorque.Size = new System.Drawing.Size(81, 26);
            this.txtMaximoTorque.TabIndex = 75;
            this.txtMaximoTorque.Text = "6";
            this.txtMaximoTorque.TextAlign = System.Windows.Forms.HorizontalAlignment.Center;
            // 
            // txtNominalTorque
            // 
            this.txtNominalTorque.Font = new System.Drawing.Font("Microsoft Sans Serif", 10F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.txtNominalTorque.Location = new System.Drawing.Point(1028, 135);
            this.txtNominalTorque.Name = "txtNominalTorque";
            this.txtNominalTorque.Size = new System.Drawing.Size(81, 26);
            this.txtNominalTorque.TabIndex = 74;
            this.txtNominalTorque.Text = "4";
            this.txtNominalTorque.TextAlign = System.Windows.Forms.HorizontalAlignment.Center;
            // 
            // txtMinimumTorque
            // 
            this.txtMinimumTorque.Font = new System.Drawing.Font("Microsoft Sans Serif", 10F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.txtMinimumTorque.Location = new System.Drawing.Point(1028, 93);
            this.txtMinimumTorque.Name = "txtMinimumTorque";
            this.txtMinimumTorque.Size = new System.Drawing.Size(81, 26);
            this.txtMinimumTorque.TabIndex = 73;
            this.txtMinimumTorque.Text = "2";
            this.txtMinimumTorque.TextAlign = System.Windows.Forms.HorizontalAlignment.Center;
            // 
            // Form1
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1130, 482);
            this.Controls.Add(this.label7);
            this.Controls.Add(this.txtTimeoutFree);
            this.Controls.Add(this.label6);
            this.Controls.Add(this.label5);
            this.Controls.Add(this.label4);
            this.Controls.Add(this.txtThresholdEndFree);
            this.Controls.Add(this.label15);
            this.Controls.Add(this.txtThresholdIniFree);
            this.Controls.Add(this.label16);
            this.Controls.Add(this.txtMaximoTorque);
            this.Controls.Add(this.txtNominalTorque);
            this.Controls.Add(this.txtMinimumTorque);
            this.Controls.Add(this.btnDisconnect);
            this.Controls.Add(this.txtIndex);
            this.Controls.Add(this.btnDisconnect2);
            this.Controls.Add(this.btnConnectIP);
            this.Controls.Add(this.label28);
            this.Controls.Add(this.txtIP);
            this.Controls.Add(this.lblUpdateTorqueSpan);
            this.Controls.Add(this.lblUpdateTorque);
            this.Controls.Add(this.button3);
            this.Controls.Add(this.label14);
            this.Controls.Add(this.label13);
            this.Controls.Add(this.lblUntighteningsCounter);
            this.Controls.Add(this.lblResultsCounter);
            this.Controls.Add(this.lblTorque1);
            this.Controls.Add(this.lblAngulo1);
            this.Controls.Add(this.label8);
            this.Controls.Add(this.lblTorque);
            this.Controls.Add(this.label9);
            this.Controls.Add(this.lblAngulo);
            this.Controls.Add(this.label12);
            this.Controls.Add(this.label11);
            this.Controls.Add(this.label10);
            this.Controls.Add(this.txtTimeoutEnd);
            this.Controls.Add(this.txtThresholdEnd);
            this.Controls.Add(this.txtThresholdIni);
            this.Controls.Add(this.btnReadData);
            this.Controls.Add(this.button2);
            this.Controls.Add(this.drpPortName);
            this.Controls.Add(this.label3);
            this.Name = "Form1";
            this.Text = "Form1";
            this.Load += new System.EventHandler(this.Form1_Load);
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion
        private System.Windows.Forms.ComboBox drpPortName;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.Button button2;
        private System.Windows.Forms.Timer timer1;
        private System.Windows.Forms.Button btnReadData;
        private System.Windows.Forms.Label label12;
        private System.Windows.Forms.Label label11;
        private System.Windows.Forms.Label label10;
        private System.Windows.Forms.TextBox txtTimeoutEnd;
        private System.Windows.Forms.TextBox txtThresholdEnd;
        private System.Windows.Forms.TextBox txtThresholdIni;
        private System.Windows.Forms.Label lblTorque1;
        private System.Windows.Forms.Label lblAngulo1;
        private System.Windows.Forms.Label label8;
        private System.Windows.Forms.Label lblTorque;
        private System.Windows.Forms.Label label9;
        private System.Windows.Forms.Label lblAngulo;
        private System.Windows.Forms.Label label14;
        private System.Windows.Forms.Label label13;
        private System.Windows.Forms.Label lblUntighteningsCounter;
        private System.Windows.Forms.Label lblResultsCounter;
        private System.Windows.Forms.Button button3;
        private System.Windows.Forms.Label lblUpdateTorqueSpan;
        private System.Windows.Forms.Label lblUpdateTorque;
        private System.Windows.Forms.Button btnDisconnect2;
        private System.Windows.Forms.Button btnConnectIP;
        private System.Windows.Forms.Label label28;
        private System.Windows.Forms.TextBox txtIP;
        private System.Windows.Forms.TextBox txtIndex;
        private System.Windows.Forms.Button btnDisconnect;
        private System.Windows.Forms.Label label7;
        private System.Windows.Forms.TextBox txtTimeoutFree;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.TextBox txtThresholdEndFree;
        private System.Windows.Forms.Label label15;
        private System.Windows.Forms.TextBox txtThresholdIniFree;
        private System.Windows.Forms.Label label16;
        private System.Windows.Forms.TextBox txtMaximoTorque;
        private System.Windows.Forms.TextBox txtNominalTorque;
        private System.Windows.Forms.TextBox txtMinimumTorque;
    }
}

